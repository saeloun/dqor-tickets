class FreeEvents::QuestionFormsController < FreeEvents::BaseController
  before_action -> { FreeEvents::Questions::Schema.require_enabled! }

  def show
    load_form
  end

  def update
    @operation = params.expect(:operation)
    @question_id = params[:question_id]
    @input = params.fetch(:question, ActionController::Parameters.new).permit(:label, :help, :type, :required, :choices).to_h
    FreeEvents::Questions::Editor.change(**access, action: @operation, revision: params.expect(:revision), question_id: @question_id, fields: @input)
    redirect_to free_event_questions_path(params[:organization_id], params[:event_id], params[:ticket_type_id]), notice: @operation == "publish" ? "Registration questions published." : "Question draft saved."
  rescue FreeEvents::Questions::Invalid => error
    @errors = error.errors
    load_form
    render :show, status: :unprocessable_content
  end

  def preview
    load_form
  end

  def export
    send_data FreeEvents::Questions::Export.csv(**access), type: "text/csv", filename: "registration-answers.csv"
  end

  private
    def access
      { user: current_user, organization_id: params[:organization_id], event_id: params[:event_id], ticket_type_id: params[:ticket_type_id] }
    end

    def load_form
      FreeEvents::Questions::Editor.read(**access) { |event, type, form| @event, @ticket_type, @form = event, type, form }
      @published = @form.persisted? ? @form.published_version : nil
    end
end
