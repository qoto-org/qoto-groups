# frozen_string_literal: true

module WellKnown
  class NodeInfoController < ActionController::Base
    include RoutingHelper

    def index
      render json: ActiveModelSerializers::SerializableResource.new({}, serializer: NodeDiscoverySerializer)
    end

    def show
      render json: ActiveModelSerializers::SerializableResource.new({}, serializer: NodeInfoSerializer, version: "2.#{ params[:format] }")
    end
  end
end
