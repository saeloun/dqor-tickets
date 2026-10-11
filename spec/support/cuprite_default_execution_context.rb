require "capybara/rspec"
require "capybara/cuprite"

module CupriteDefaultExecutionContext
  private
    def subscribe_execution_context_created
      on("Runtime.executionContextCreated") do |params|
        next unless params.dig("context", "auxData", "isDefault") == true

        context_id = params.dig("context", "id")
        frame_id = params.dig("context", "auxData", "frameId")
        unless @main_frame.id
          root_frame = command("Page.getFrameTree").dig("frameTree", "frame", "id")
          if frame_id == root_frame
            @main_frame.id = frame_id
            @frames.put_if_absent(frame_id, @main_frame)
          end
        end
        frame = @frames.fetch_or_store(frame_id, Ferrum::Frame.new(frame_id, self))
        frame.execution_id = context_id
      end
    end
end

Capybara::Cuprite::Page.prepend(CupriteDefaultExecutionContext)
