from django.conf.urls import url

from . import views

urlpatterns = [
    url(r'^list$', views.App2ListView.as_view(), name='app2_list'),
]
