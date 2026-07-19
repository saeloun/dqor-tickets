require "rails_helper"

RSpec.describe DeliverOrderConfirmationJob, type: :job do
  it "emails the paid buyer and re-enqueues document generation when rendering keeps failing" do
    order = create(:order, :paid)
    create(:ticket, order:)
    Invoice.issue_for!(order)
    allow(PdfRenderer).to receive(:render).and_raise(Ferrum::DeadBrowserError)

    expect do
      perform_enqueued_jobs(only: MailDeliveryJob) do
        described_class.perform_now(order)
      end
    end.to change(ActionMailer::Base.deliveries, :count).by(1)

    mail = ActionMailer::Base.deliveries.last
    expect(order.reload).to be_paid
    expect(order.metadata).to include("confirmation_enqueued_at")
    expect(mail.attachments).to be_empty
    expect(mail.body.encoded).to include("being prepared", "/orders/#{order.code}")
    expect(GenerateOrderDocumentsJob).to have_been_enqueued.with(order)
  end
end
