require 'forwardable'

module Dragonfly
  class Job

    # Exceptions
    class AppDoesNotMatch < StandardError; end
    class JobAlreadyApplied < StandardError; end
    class NothingToProcess < StandardError; end
    class NothingToEncode < StandardError; end
    class NothingToAnalyse < StandardError; end
    class InvalidArray < StandardError; end
    
    include Loggable
    
    extend Forwardable
    def_delegators :to_temp_object, :data, :size, :name
    def_delegators :steps, :any?, :empty?
    
    class Step
      
      class << self
        # Dragonfly::Job::Fetch -> 'Fetch'
        def basename
          @basename ||= name.split('::').last
        end
        # Dragonfly::Job::Fetch -> :fetch
        def step_name
          @step_name ||= basename.gsub(/[A-Z]/){ "_#{$&.downcase}" }.sub('_','').to_sym
        end
        # Dragonfly::Job::Fetch -> :f
        def abbreviation
          @abbreviation ||= basename.scan(/[A-Z]/).join.downcase.to_sym
        end
      end
      
      def initialize(*args)
        @args = args
      end
      attr_reader :args
      def inspect
        "#{self.class.step_name}(#{args.map{|a| a.inspect }.join(', ')})"
      end
    end

    class Fetch < Step
      def uid
        args.first
      end
      def apply(job)
        job.temp_object = TempObject.new(*job.app.datastore.retrieve(uid))
      end
    end
    
    class Process < Step
      def name
        args.first
      end
      def arguments
        args[1..-1]
      end
      def apply(job)
        raise NothingToProcess, "Can't process because temp object has not been initialized. Need to fetch first?" unless job.temp_object
        job.temp_object = TempObject.new job.app.processor.process(job.temp_object, name, *arguments)
      end
    end
    
    class Encode < Step
      def format
        args.first
      end
      def arguments
        args[1..-1]
      end
      def apply(job)
        raise NothingToEncode, "Can't encode because temp object has not been initialized. Need to fetch first?" unless job.temp_object
        job.temp_object = TempObject.new job.app.encoder.encode(job.temp_object, format, *arguments)
      end
    end

    class Generate < Step
      def apply(job)
        job.temp_object = TempObject.new job.app.generator.generate(*args)
      end
    end

    STEPS = [
      Fetch,
      Process,
      Encode,
      Generate
    ]
    
    # Class methods
    class << self
      
      def from_a(steps_array, app)
        unless steps_array.is_a?(Array) &&
               steps_array.all?{|s| s.is_a?(Array) && step_abbreviations[s.first] }
          raise InvalidArray, "can't define a job from #{steps_array.inspect}"
        end
        job = Job.new(app)
        steps_array.each do |step_array|
          step_class = step_abbreviations[step_array.shift]
          job.steps << step_class.new(*step_array)
        end
        job
      end
      
      def deserialize(string, app)
        from_a(Serializer.marshal_decode(string), app)
      end
      
      def step_abbreviations
        @step_abbreviations ||= STEPS.inject({}){|hash, step_class| hash[step_class.abbreviation] = step_class; hash }
      end
      
      def step_names
        @step_names ||= STEPS.map{|step_class| step_class.step_name }
      end

    end

    # Instance methods

    def initialize(app, temp_object=nil)
      @app = app
      self.extend app.analyser.analysis_methods
      self.extend app.job_definitions
      @steps = []
      @next_step_index = 0
      @temp_object = temp_object
    end
    
    # Used by 'dup' and 'clone'
    def initialize_copy(other)
      self.steps = other.steps.dup
      self.extend app.analyser.analysis_methods
      self.extend app.job_definitions
    end
    
    attr_accessor :temp_object
    attr_reader :app, :steps

    # define fetch(), fetch!(), process(), etc.
    STEPS.each do |step_class|
      class_eval %(
        def #{step_class.step_name}(*args)
          new_job = self.dup
          new_job.steps << #{step_class}.new(*args)
          new_job
        end
        
        def #{step_class.step_name}!(*args)
          steps << #{step_class}.new(*args)
          self
        end
      )
    end
    
    def analyse(method, *args)
      unless to_temp_object
        raise NothingToAnalyse, "Can't analyse because temp object has not been initialized. Need to fetch first?"
      end
      analyser.analyse(to_temp_object, method, *args)
    end

    def format
      encoding_steps.last.format if encoding_steps.any?
    end

    def mime_type
      app.mime_type_for(format) if format
    end

    def +(other_job)
      unless app == other_job.app
        raise AppDoesNotMatch, "Cannot add jobs belonging to different apps (#{app} is not #{other_job.app})"
      end
      unless other_job.applied_steps.empty?
        raise JobAlreadyApplied, "Cannot add jobs when the second one has already been applied (#{other_job})"
      end
      new_job = self.class.new(app, temp_object)
      new_job.steps = steps + other_job.steps
      new_job.next_step_index = next_step_index
      new_job
    end
    
    def apply
      pending_steps.each{|step| step.apply(self) }
      self.next_step_index = steps.length
      self
    end
    
    def to_temp_object
      apply
      temp_object
    end
    
    def applied_steps
      steps[0...next_step_index]
    end
    
    def pending_steps
      steps[next_step_index..-1]
    end

    def to_a
      steps.map{|step|
        [step.class.abbreviation, *step.args]
      }
    end

    def serialize
      Serializer.marshal_encode(to_a)
    end

    def to_app
      JobEndpoint.new(self)
    end
    
    def to_response
      to_app.call
    end

    def url
      app.url_for(self)
    end

    def inspect
      to_s.sub(/>$/, " app=#{app}, steps=#{steps.inspect}, temp_object=#{temp_object.inspect}, steps applied:#{applied_steps.length}/#{steps.length} >")
    end

    protected

    attr_writer :steps
    attr_accessor :next_step_index

    private
    
    def encoding_steps
      steps.select{|step| step.is_a?(Encode) }
    end

  end
end
