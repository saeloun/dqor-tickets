class Hiring::AccessEvent < ApplicationRecord
  belongs_to :application, class_name: "Hiring::Application"
  belongs_to :user
end
