class ScreeningsController < ApplicationController
  def index
    @venues = Venue.order(:name)

    # Eager load film and venue: the index renders both for every row, so without
    # this the view fires an N+1 (one query per screening, per association).
    @screenings = Screening.includes(:film, :venue).order(:starts_at)

    @screenings = @screenings.where(venue_id: params[:venue_id]) if params[:venue_id].present?

    if (date = parsed_date(params[:date]))
      @screenings = @screenings.where(starts_at: date.all_day)
    end

    if params[:q].present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].strip)}%"
      @screenings = @screenings.references(:film).where("films.title ILIKE ?", pattern)
    end
  end

  private

  def parsed_date(value)
    return if value.blank?

    Date.parse(value)
  rescue ArgumentError
    nil
  end
end
