module Praxis

  CONTEXT_FOR = {
    params: [Attributor::AttributeResolver::ROOT_PREFIX, "params".freeze],
    headers: [Attributor::AttributeResolver::ROOT_PREFIX, "headers".freeze],
    payload: [Attributor::AttributeResolver::ROOT_PREFIX, "payload".freeze]
  }.freeze

  class Dispatcher
    attr_reader :controller, :action, :request, :application

    @deferred_callbacks = Hash.new do |hash,stage|
      hash[stage] = {before: [], after:[]}
    end

    class << self
      attr_reader :deferred_callbacks
    end

    def self.before(*stage_path, **conditions, &block)
      @deferred_callbacks[:before] << [conditions, block]
    end

    def self.after(*stage_path, **conditions, &block)
      @deferred_callbacks[:after] << [conditions, block]
    end

    def self.current(thread: Thread.current, application: Application.instance)
      thread[:praxis_dispatcher] ||= self.new(application: application)
    end

    def initialize(application: Application.instance)
      @stages = []
      @application = application
      setup_stages!
    end

    def setup_stages!
      @stages << RequestStages::LoadRequest.new(:load_request, self)
      @stages << RequestStages::Validate.new(:validate, self)
      @stages << RequestStages::Action.new(:action, self)
      @stages << RequestStages::Response.new(:response, self)
      setup_deferred_callbacks!
    end

    def setup_deferred_callbacks!
      self.class.deferred_callbacks.each do |stage_name, callbacks|
        callbacks[:before].each do |(*stage_path, block)|
          self.before(stage_name, *stage_path, &block)
        end

        callbacks[:after].each do |(*stage_path, block)|
          self.after(stage_name, *stage_path, &block)
        end
      end
    end

    def before(*stage_path, &block)
      stage_name = stage_path.shift
      stages.find { |stage| stage.name == stage_name }.before(*stage_path, &block)
    end

    def after(*stage_path, &block)
      stage_name = stage_path.shift
      stages.find { |stage| stage.name == stage_name }.after(*stage_path, &block)
    end

    def dispatch(controller_class, action, request)
      @controller = controller_class.new(request)
      @action = action
      @request = request

      @stages.each do |stage|
        result = stage.run
        case result
        when Response
          return result.finish
        end
      end

      controller.response.finish
    rescue => e
      response = Responses::InternalServerError.new(error: e)
      response.request = controller.request
      response.finish
    ensure
      @controller = nil
      @action = nil
      @request = nil
    end
   
    
    def reset_cache!
      return unless Praxis::Blueprint.caching_enabled?

      Praxis::Blueprint.cache = Hash.new do |hash, key|
        hash[key] = Hash.new
      end
    end

  end
end
