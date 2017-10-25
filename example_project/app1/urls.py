from django.conf.urls import url

from . import views

urlpatterns = [
    url(r'^list$', views.App1ListView.as_view(), name='app1_list'),
]
