class FaqsController < ApplicationController
  allow_unauthenticated_access

  def index
    @faqs = Faq.published.ordered
  end
end
