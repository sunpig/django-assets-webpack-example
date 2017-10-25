from django.views.generic.base import TemplateView


class App1ListView(TemplateView):
    template_name = 'app1/app1_list.html'
