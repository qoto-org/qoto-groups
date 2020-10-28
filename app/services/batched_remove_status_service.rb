# frozen_string_literal: true

class BatchedRemoveStatusService < BaseService
  include Redisable

  # Delete given statuses and reblogs of them
  # Dispatch PuSH updates of the deleted statuses, but only local ones
  # Dispatch Salmon deletes, unique per domain, of the deleted statuses, but only local ones
  # Remove statuses from home feeds
  # Push delete events to streaming API for home feeds and public feeds
  # @param [Enumerable<Status>] statuses A preferably batched array of statuses
  # @param [Hash] options
  # @option [Boolean] :skip_side_effects
  def call(statuses, **options)
    statuses = Status.where(id: statuses.map(&:id)).includes(:account).flat_map { |status| [status] + status.reblogs.includes(:account).to_a }

    @mentions = statuses.each_with_object({}) { |s, h| h[s.id] = s.active_mentions.includes(:account).to_a }
    @tags     = statuses.each_with_object({}) { |s, h| h[s.id] = s.tags.pluck(:name) }

    @json_payloads = statuses.each_with_object({}) { |s, h| h[s.id] = Oj.dump(event: :delete, payload: s.id.to_s) }

    # Ensure that rendered XML reflects destroyed state
    statuses.each do |status|
      status.mark_for_mass_destruction!
      status.destroy
    end

    return if options[:skip_side_effects]

    # Cannot be batched
    statuses.each do |status|
      unpush_from_public_timelines(status)
    end
  end

  private

  def unpush_from_public_timelines(status)
    return unless status.distributable?

    payload = @json_payloads[status.id]

    redis.pipelined do
      if status.local?
        redis.publish('timeline:public:local', payload)
        redis.publish('timeline:public:local:media', payload) if status.media_attachments.any?
      end

      if status.public_visibility?
        @tags[status.id].each do |hashtag|
          redis.publish("timeline:hashtag:#{hashtag.mb_chars.downcase}", payload)
          redis.publish("timeline:hashtag:#{hashtag.mb_chars.downcase}:local", payload) if status.local?
        end
      end
    end
  end
end
