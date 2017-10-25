#!/usr/bin/env bash

VAGRANT_DIR="/vagrant"
PROJECT_NAME="example_project"
USERNAME="ubuntu"
USER_DIR="/home/$USERNAME"
PROJECT_DATABASE_NAME="$PROJECT_NAME""_db"
PROJECT_DATABASE_USER="$PROJECT_NAME""_user"
PROJECT_DATABASE_PASSWORD=`openssl rand -hex 8`
PROJECT_SECRET_KEY=`openssl rand -hex 8`

apt-get update
apt-get install --yes build-essential  # for the "make" command, and for installing nvm
apt-get install --yes python3  # install the default python3 for bootstrapping. In the actual virtualenv for app dev purposes, lock down the python version that will be used.
apt-get install --yes python3-pip  # install the default pip3 for use with python3.
apt-get install --yes virtualenv  # install virtualenv for setting up virtualenvs for isolated app dev
apt-get install --yes postgresql-9.5  # Even though later postgres versions are available, 9.5 is fine. 
apt-get install --yes libpq-dev  # for building client libraries, including the psycopg2 pip module for connecting to PG databases
apt-get install --yes python3.5-dev  # contains the Python.h header files needed for building psycopg2 for python 3.5
apt-get install --yes libssl-dev  # for installing nvm
apt-get install --yes nginx  # for emulating production environment

pip3 install --upgrade pip


###############################################################################
# Virtualenvs setup

# Create virtualenvs directory
if [ ! -d "$USER_DIR/.envs" ]; then
	mkdir -p $USER_DIR/.envs
	chown -R $USERNAME:$USERNAME $USER_DIR/.envs
fi

# Make new virtualenv for example project with python3.5
if [ ! -d "$USER_DIR/.envs/$PROJECT_NAME" ]; then
	# Run command file as the VM user
	PYTHON_VENV_INSTALL_SCRIPT=$USER_DIR/python_venv_install.sh
	echo "cd /home/ubuntu/.envs;virtualenv $PROJECT_NAME -p python3.5" > $PYTHON_VENV_INSTALL_SCRIPT
	sudo su -l $USERNAME $PYTHON_VENV_INSTALL_SCRIPT
	rm $PYTHON_VENV_INSTALL_SCRIPT
fi


###############################################################################
# NodeJS and npm: use nvm (https://github.com/creationix/nvm) to install
# a stable LTS version of node. Note that this version of node will only
# be available to the VM user! This is OK, because in this example project
# we're only using node for development & deployment (compile, compress,
# & concat client-side assets). We're not using it as a production server.

# Manual install: use a pre-downloaded version of the nvm.sh script
if [ ! -f "$USER_DIR/.nvm/nvm.sh" ]; then
	mkdir -p $USER_DIR/.nvm
	cp $VAGRANT_DIR/provision/files/nvm.sh $USER_DIR/.nvm/nvm.sh
	chown --recursive $USERNAME:$USERNAME $USER_DIR/.nvm
	chmod 0644 $USER_DIR/.nvm/nvm.sh

	# Write a command file with nvm and node setup commands to be run
	NODE_INSTALL_SCRIPT=$USER_DIR/node_install.sh
	cat <<EOT > $NODE_INSTALL_SCRIPT
	source $USER_DIR/.nvm/nvm.sh
	nvm install 8.8.0
	npm install --global grunt-cli testem jshint
EOT

	# Run the command file as the VM user (vagrant)
	sudo su -l $USERNAME $NODE_INSTALL_SCRIPT

	# Clean up the command file
	rm $NODE_INSTALL_SCRIPT
fi


###############################################################################
# Postgres setup

# Write a command file with nvm and node setup commands to be run
DATABASE_INIT_SCRIPT=$USER_DIR/database_init.sh
cat <<EOT > $DATABASE_INIT_SCRIPT
psql --command "drop database if exists $PROJECT_DATABASE_NAME"
psql --command "drop user if exists $PROJECT_DATABASE_USER"
psql --command "create user $PROJECT_DATABASE_USER with createdb password '$PROJECT_DATABASE_PASSWORD'"
createdb --owner=$PROJECT_DATABASE_USER $PROJECT_DATABASE_NAME
EOT
# Run the command file as the postgres user
sudo su -l postgres $DATABASE_INIT_SCRIPT

# Clean up the command file
# rm $DATABASE_INIT_SCRIPT

# Note that by default, any new user can create tables in the public schema of a postgres database.
# So no need for granting additional permissions right now.


###############################################################################
# Build a file with environment variables for 12-factor app configuration
# These values will be read into environment variables for the VM user's login shell,
# and can be re-used by uwsgi in the pseudo-production mode. 
if [ ! -d "/var/apps/$PROJECT_NAME" ]; then
	mkdir -p /var/apps/$PROJECT_NAME
	chown -R root:adm /var/apps/$PROJECT_NAME
	chmod 0775 /var/apps/$PROJECT_NAME
fi

cp $VAGRANT_DIR/provision/files/project.env.tmpl /var/apps/$PROJECT_NAME/$PROJECT_NAME.env
chown -R root:adm /var/apps/$PROJECT_NAME/$PROJECT_NAME.env

# Variable substitution
sed -i -e "s/{{PROJECT_SECRET_KEY}}/$PROJECT_SECRET_KEY/g" -e "s/{{PROJECT_DATABASE_NAME}}/$PROJECT_DATABASE_NAME/g" -e "s/{{PROJECT_DATABASE_USER}}/$PROJECT_DATABASE_USER/g" -e "s/{{PROJECT_DATABASE_PASSWORD}}/$PROJECT_DATABASE_PASSWORD/g" /var/apps/$PROJECT_NAME/$PROJECT_NAME.env


###############################################################################
# Add useful things to the VM user's login shell
cp $VAGRANT_DIR/provision/files/bashrc_extra.tmpl $USER_DIR/.bashrc_extra

# Look for "{{PROJECT_NAME}}" template variables in the bashrc_extra.tmpl and replace with real values
sed -i "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" $USER_DIR/.bashrc_extra

chown --recursive $USERNAME:$USERNAME $USER_DIR/.bashrc_extra

if ! grep --quiet ".bashrc_extra" $USER_DIR/.bashrc
then
    echo "source .bashrc_extra" >> $USER_DIR/.bashrc
fi


###############################################################################
# Create a pseudo-production environment in the VM to mimic production in certain key aspects:
# * uwsgi in emperor mode
# * uwsgi will run the app as the www-data user
# * app will be stored in /var/apps/#{project_name}. Each deploy will go
#   into a timestamped subdirectory; the current version will be symlinked to a `current` directory.
# * uwsgi log: /var/log/uwsgi/#{project_name}.log
# * nginx access log: /var/log/nginx/#{project_name}.access.log
# * nginx error log: /var/log/nginx/#{project_name}.error.log
# * uwsgi socket: /var/run/uwsgi/#{project_name}.sock (owner: www-data:www-data)
#
# The idea being:
# * In development, work with the django development server.
# * Access the development server from the host machine as localhost:8000
# * From within the VM, deploy to the VM-based pseudo-production environment
#   * When you ssh into the VM, you're using the 'ubuntu' user. All deployment tools (e.g. node) can assume this user.
#   * The app in the pseudo-production environment will be run under the www-data account.
# * From the host machine, access the app via nginx at localhost:8080
#
###############################################################################

# The www-data will be running the app, but the ubuntu user
# is doing all the deployment. Add the ubuntu (VM) user to
# the www-data group, so we can enable group permissions and have
# ubuntu be able to do everything.
usermod -a -G www-data $USERNAME

# Install uwsgi as root. Running pip3 install as root will put the binary at /usr/local/bin/uwsgi
pip3 install uwsgi

# Create a config directory for uwsgi
if [ ! -d "/etc/uwsgi/sites" ]; then
	mkdir -p /etc/uwsgi/sites
	chmod 0775 /etc/uwsgi/sites
fi

# Create an ini file for running our app under uwsgi
cp $VAGRANT_DIR/provision/files/project_uwsgi.ini.tmpl "/etc/uwsgi/sites/$PROJECT_NAME""_uwsgi.ini"
chmod 0644 "/etc/uwsgi/sites/$PROJECT_NAME""_uwsgi.ini"
# Variable interpolation
sed -i "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "/etc/uwsgi/sites/$PROJECT_NAME""_uwsgi.ini"

# Ensure a log directory exists
if [ ! -d "/var/log/uwsgi" ]; then
	mkdir -p /var/log/uwsgi
	chmod 0775 /var/log/uwsgi
fi

# Ensure a socket directory exists
if [ ! -d "/var/run/uwsgi" ]; then
	mkdir -p /var/run/uwsgi
	chmod 0775 /var/run/uwsgi
fi

# Set up uwsgi to run as a service:
# 1: Add service definition
cp $VAGRANT_DIR/provision/files/uwsgi.service /etc/systemd/system/uwsgi.service
chmod 0644 /etc/systemd/system/uwsgi.service
# 2: Start the uwsgi service, and enable it to run at startup
systemctl daemon-reload
systemctl start uwsgi
systemctl enable uwsgi

# Set up nginx to talk to uwsgi 
# 1: Remove the default site
if [ -f "/etc/nginx/sites-enabled/default" ]; then
	rm /etc/nginx/sites-enabled/default
fi
# 2: Define the new site
cp $VAGRANT_DIR/provision/files/project_nginx_site.tmpl "/etc/nginx/sites-available/$PROJECT_NAME""_nginx_site"
chmod 0644 "/etc/nginx/sites-available/$PROJECT_NAME""_nginx_site"
sed -i "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "/etc/nginx/sites-available/$PROJECT_NAME""_nginx_site"
# 3: Enable the new site
if [ ! -f "/etc/nginx/sites-enabled/$PROJECT_NAME""_nginx_site" ]; then
	ln -s "/etc/nginx/sites-available/$PROJECT_NAME""_nginx_site" "/etc/nginx/sites-enabled/$PROJECT_NAME""_nginx_site"
fi
# 4: Restart nginx to reload config
systemctl restart nginx

