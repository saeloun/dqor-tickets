module FreeEvents::Questions
  class Invalid < StandardError
    attr_reader :errors
    def initialize(errors)
      @errors = errors
      super(errors.values.join(". "))
    end
  end
end
