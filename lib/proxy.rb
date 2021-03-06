require 'proxy/action_controller/abstract_request'
require 'proxy/action_controller/base'
require 'proxy/action_controller/named_route_collection'
require 'proxy/action_controller/url_rewriter'
require 'proxy/action_view/url_helper'

module Proxy
  mattr_accessor :replace_host_with_proc
  self.replace_host_with_proc = proc { |request| }

  def self.replace_host_with(&block)
    self.replace_host_with_proc = block
  end

  private

    def self.before_dispatch(dispatcher)
      request = dispatcher.instance_variable_get('@request') || dispatcher.instance_variable_get('@env')
      request = Rack::Request.new(request) if request.is_a?(Hash)
      new_host = replace_host_with_proc.call(request)
      if /([^\.]+\.[^\.]+)$/.match(request.host)
        original_host = ".#{$1}"
      else
        original_host = request.host
      end
      request.env['rack.session.options'].merge!(:domain => original_host) # force cookie that matches original domain without subdomain
      request.env['HTTP_X_FORWARDED_HOST'] = [request.host, new_host].join(', ') unless new_host.blank?
    end
end

ActionDispatch::Callbacks.before do |dispatcher|
  Proxy.send :before_dispatch, dispatcher
end

ActionDispatch::Request.send :include, Proxy::ActionController::AbstractRequest
ActionController::Base.send :include, Proxy::ActionController::Base
ActionController::Routing::RouteSet::NamedRouteCollection.send :include, Proxy::ActionController::NamedRouteCollection
ActionController::UrlRewriter.send :include, Proxy::ActionController::UrlRewriter
ActionView::Base.send :include, Proxy::ActionView::UrlHelper

unless ActionController::UrlWriter.respond_to?(:default_url_options)
  ActionController::Base.class_eval do
    include ActionController::UrlWriter

    def default_url_options_with_backwards_compatibility(*args)
      default_url_options_without_backwards_compatibility
    end
    alias_method_chain :default_url_options, :backwards_compatibility
  end

  class << ActionController::UrlWriter
    delegate :default_url_options, :default_url_options=, :to => ::ActionController::Base
  end
end
