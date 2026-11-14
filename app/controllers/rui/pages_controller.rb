require "railsui"

class Rui::PagesController < ApplicationController
  before_action :load_score_preview, only: %i[score score_data download_musicxml]

  ::Railsui.config.pages.each do |page|
    define_method(page.to_sym) do
      render "rui/pages/#{page}", layout: determine_layout(page)
    end
  end

  def tools
    render "rui/pages/tools", layout: "rui/railsui_admin"
  end

  def convert
    mxl = PdfToMusicxmlConverter.new(params[:pdf]).call
    metadata = PdfScoreMetadataExtractor.new(params[:pdf]).call
    musicxml = MusicxmlScoreProcessor.from_content(mxl, filename: "converted-score.mxl", **metadata)
    token = MusicxmlScorePreviewStore.create(musicxml, original_filename: params[:pdf].original_filename)
    redirect_to rui_tools_score_path(token)
  rescue PdfToMusicxmlConverter::ConversionError, MusicxmlScoreProcessor::ConversionError => error
    flash.now[:alert] = error.message
    render "rui/pages/tools", layout: "rui/railsui_admin", status: :unprocessable_entity
  end

  def visualize
    musicxml = MusicxmlScoreProcessor.new(params[:score]).call
    token = MusicxmlScorePreviewStore.create(musicxml, original_filename: params[:score].original_filename)
    render json: { preview_url: rui_tools_score_path(token) }
  rescue MusicxmlScoreProcessor::ConversionError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def score
    render "rui/pages/score", layout: "rui/railsui_admin"
  end

  def score_data
    send_data @score_musicxml,
      type: "application/vnd.recordare.musicxml+xml",
      disposition: "inline"
  end

  def download_musicxml
    send_data @score_musicxml,
      filename: "#{@score_download_basename}.musicxml",
      type: "application/vnd.recordare.musicxml+xml",
      disposition: "attachment"
  end

  private

  def load_score_preview
    @score_musicxml = MusicxmlScorePreviewStore.read(params[:token])
    @score_download_basename = MusicxmlScorePreviewStore.download_basename(params[:token])
  rescue MusicxmlScorePreviewStore::NotFound
    render plain: "This score preview has expired or is unavailable.", status: :not_found
  end

  def determine_layout(page)
    page_obj = ::Railsui::Pages.installed_pages[page.to_s]

    return "rui/railsui_#{page_obj['layout']}" if custom_layout_exists?(page_obj)
    return "rui/railsui_admin" if admin_layout?(page_obj)
    "rui/railsui"
  end

  def custom_layout_exists?(page_obj)
    page_obj['layout'].present? &&
      lookup_context.exists?("layouts/rui/railsui_#{page_obj['layout']}")
  end

  def admin_layout?(page_obj)
    page_obj['namespace'] == 'admin' &&
      lookup_context.exists?("layouts/rui/railsui_admin") &&
      !page_obj['layout'].present?
  end
end
