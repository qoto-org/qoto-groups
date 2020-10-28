# frozen_string_literal: true
# == Schema Information
#
# Table name: lists
#
#  id         :bigint(8)        not null, primary key
#  account_id :bigint(8)        not null
#  title      :string           default(""), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class List < ApplicationRecord
  include Paginable

  PER_ACCOUNT_LIMIT = 50

  belongs_to :account, optional: true

  has_many :list_accounts, inverse_of: :list, dependent: :destroy
  has_many :accounts, through: :list_accounts

  validates :title, presence: true

  validates_each :account_id, on: :create do |record, _attr, value|
    record.errors.add(:base, I18n.t('lists.errors.limit')) if List.where(account_id: value).count >= PER_ACCOUNT_LIMIT
  end
end
