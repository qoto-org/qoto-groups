# frozen_string_literal: true

class RemovalWorker
  include Sidekiq::Worker

  def perform(status_id, options = {})
    RemoveStatusService.new.call(Status.find(status_id), options)
  rescue ActiveRecord::RecordNotFound
    true
  end
end
