class Avo::Resources::AdminUser < Avo::BaseResource
  self.title = :email

  def fields
    field :id, as: :id
    field :name, as: :text
    field :email, as: :text, sortable: true
    field :role, as: :select, enum: ::AdminUser.roles,
      help: "Desk accounts can only use the check-in scanner. Admins have full access."
    field :password, as: :password, help: "Set on create; leave blank to keep the current password."
    field :created_at, as: :date_time, only_on: :index, sortable: true
  end
end
