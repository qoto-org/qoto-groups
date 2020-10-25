# frozen_string_literal: true

class Api::V1::StatusesController < Api::BaseController
  include Authorization

  before_action -> { authorize_if_got_token! :read, :'read:statuses' }, except: [:create, :destroy]
  before_action -> { doorkeeper_authorize! :write, :'write:statuses' }, only:   [:create, :destroy]
  before_action :require_user!, except:  [:show, :context]
  before_action :set_status, only:       [:show, :context]
  before_action :set_thread, only:       [:create]
  before_action :set_circle, only:       [:create]

  override_rate_limit_headers :create, family: :statuses

  # This API was originally unlimited, pagination cannot be introduced without
  # breaking backwards-compatibility. Arbitrarily high number to cover most
  # conversations as quasi-unlimited, it would be too much work to render more
  # than this anyway
  CONTEXT_LIMIT = 4_096

  def show
    @status = cache_collection([@status], Status).first
    render json: @status, serializer: REST::StatusSerializer
  end

  def context
    ancestors_results   = @status.in_reply_to_id.nil? ? [] : @status.ancestors(CONTEXT_LIMIT, current_account)
    descendants_results = @status.descendants(CONTEXT_LIMIT, current_account)
    loaded_ancestors    = cache_collection(ancestors_results, Status)
    loaded_descendants  = cache_collection(descendants_results, Status)

    @context = Context.new(ancestors: loaded_ancestors, descendants: loaded_descendants)
    statuses = [@status] + @context.ancestors + @context.descendants
    accountIds = statuses.filter(&:quote?).map { |status| status.quote.account_id }.uniq

    render json: @context, serializer: REST::ContextSerializer, relationships: StatusRelationshipsPresenter.new(statuses, current_user&.account_id), account_relationships: AccountRelationshipsPresenter.new(accountIds, current_user&.account_id)
  end

  def create
    @status = PostStatusService.new.call(current_user.account,
                                         text: status_params[:status],
                                         thread: @thread,
                                         circle: @circle,
                                         media_ids: status_params[:media_ids],
                                         sensitive: status_params[:sensitive],
                                         spoiler_text: status_params[:spoiler_text],
                                         visibility: status_params[:visibility],
                                         scheduled_at: status_params[:scheduled_at],
                                         expires_at: status_params[:expires_at],
                                         expires_action: status_params[:expires_action],
                                         application: doorkeeper_token.application,
                                         poll: status_params[:poll],
                                         idempotency: request.headers['Idempotency-Key'],
                                         with_rate_limit: true,
                                         quote_id: status_params[:quote_id].presence,
                                         content_type: status_params[:content_type], #'text/markdown'
                                         local_only: status_params[:local_only])

    render json: @status, serializer: @status.is_a?(ScheduledStatus) ? REST::ScheduledStatusSerializer : REST::StatusSerializer
  end

  def destroy
    @status = Status.include_expired.where(account_id: current_account.id).find(params[:id])
    authorize @status, :destroy?

    @status.discard
    RemovalWorker.perform_async(@status.id, redraft: true)
    @status.account.statuses_count = @status.account.statuses_count - 1

    render json: @status, serializer: REST::StatusSerializer, source_requested: true
  end

  private

  def set_status
    @status = Status.include_expired(current_account).find(params[:id])
    authorize @status, :show?
  rescue Mastodon::NotPermittedError
    not_found
  end

  def set_thread
    @thread = status_params[:in_reply_to_id].blank? ? nil : Status.find(status_params[:in_reply_to_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: I18n.t('statuses.errors.in_reply_not_found') }, status: 404
  end

  def set_circle
    @circle = status_params[:circle_id].blank? ? nil : current_account.owned_circles.find(status_params[:circle_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: I18n.t('statuses.errors.circle_not_found') }, status: 404
  end

  def status_params
    params.permit(
      :status,
      :in_reply_to_id,
      :circle_id,
      :sensitive,
      :spoiler_text,
      :visibility,
      :scheduled_at,
      :quote_id,
      :expires_at,
      :expires_action,
      :content_type,
      :local_only,
      media_ids: [],
      poll: [
        :multiple,
        :hide_totals,
        :expires_in,
        options: [],
      ]
    )
  end

  def pagination_params(core_params)
    params.slice(:limit).permit(:limit).merge(core_params)
  end
end
