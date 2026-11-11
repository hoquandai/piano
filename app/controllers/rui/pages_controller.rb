require "railsui"

class Rui::PagesController < ApplicationController
  ::Railsui.config.pages.each do |page|
    define_method(page.to_sym) do
      render "rui/pages/#{page}", layout: determine_layout(page)
    end
  end

  def tools
    render "rui/pages/tools", layout: "rui/railsui_admin"
  end

  def convert
    musicxml = PdfToMusicxmlConverter.new(params[:pdf]).call

    send_data musicxml,
      filename: "converted-score.mxl",
      type: "application/vnd.recordare.musicxml",
      disposition: "attachment"
  rescue PdfToMusicxmlConverter::ConversionError => error
    flash.now[:alert] = error.message
    render "rui/pages/tools", layout: "rui/railsui_admin", status: :unprocessable_entity
  end

  private

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
