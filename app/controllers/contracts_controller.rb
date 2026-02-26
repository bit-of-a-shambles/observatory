# frozen_string_literal: true

class ContractsController < ApplicationController
  include ActionView::Helpers::NumberHelper

  PER_PAGE = 50

  def index
    scope = Contract.includes(:contracting_entity, :winners, :data_source)

    if params[:q].present?
      scope = scope.where("object LIKE ?", "%#{params[:q]}%")
    end

    if params[:procedure_type].present?
      scope = scope.where(procedure_type: params[:procedure_type])
    end

    if params[:country].present?
      scope = scope.where(country_code: params[:country])
    end

    @total        = scope.count
    @page         = [ params[:page].to_i, 1 ].max
    @total_pages  = (@total.to_f / PER_PAGE).ceil
    @contracts    = scope.order(celebration_date: :desc, id: :desc)
                         .limit(PER_PAGE).offset((@page - 1) * PER_PAGE)

    @procedure_types = Contract.distinct.pluck(:procedure_type).compact.sort
    @countries       = Contract.distinct.pluck(:country_code).compact.sort
  end

  def show
    @contract = Contract.includes(:contracting_entity, :winners, :data_source).find(params[:id])
  end
end
