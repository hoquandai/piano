require "tempfile"
require "stringio"
require "zip"

class MusicxmlScoreProcessor
  MAX_FILE_SIZE = 20 * 1024 * 1024
  MAX_CONTAINER_SIZE = 1024 * 1024
  XML_EXTENSIONS = %w[.xml .musicxml].freeze
  COMPRESSED_EXTENSION = ".mxl"

  class ConversionError < StandardError; end

  def self.from_content(content, filename:, title: nil, composer: nil, source_metadata: {}, source_page_texts: [])
    Tempfile.create([ "musicxml-score", File.extname(filename) ]) do |tempfile|
      tempfile.binmode
      tempfile.write(content)
      tempfile.rewind

      upload = ActionDispatch::Http::UploadedFile.new(
        tempfile: tempfile,
        filename: filename,
        type: "application/vnd.recordare.musicxml"
      )
      new(upload, title: title, composer: composer, source_metadata: source_metadata,
        source_page_texts: source_page_texts).call
    end
  end

  def initialize(upload, title: nil, composer: nil, source_metadata: {}, source_page_texts: [])
    @upload = upload
    @title = title.to_s.strip.presence
    @composer = composer.to_s.strip.presence
    @source_metadata = source_metadata
    @source_page_texts = source_page_texts
  end

  def call
    validate_upload!
    xml = @upload.original_filename.downcase.end_with?(COMPRESSED_EXTENSION) ? read_compressed_xml : read_plain_xml
    document = parse_xml(xml)
    validate_score!(document)
    remove_fingering_annotations(document)
    add_score_metadata(document)
    add_source_pdf_content(document.root)
    document.to_xml
  end

  private

  def validate_upload!
    unless @upload.is_a?(ActionDispatch::Http::UploadedFile)
      raise ConversionError, "Choose a MusicXML file to preview."
    end

    extension = File.extname(@upload.original_filename.to_s).downcase
    unless XML_EXTENSIONS.include?(extension) || extension == COMPRESSED_EXTENSION
      raise ConversionError, "Upload an .xml, .musicxml, or .mxl file."
    end

    if @upload.size.zero?
      raise ConversionError, "The uploaded MusicXML file is empty."
    end

    if @upload.size > MAX_FILE_SIZE
      raise ConversionError, "The uploaded file must be 20 MB or smaller."
    end
  end

  def read_plain_xml
    read_upload
  end

  def read_compressed_xml
    musicxml = nil
    Zip::File.open_buffer(StringIO.new(read_upload)) do |archive|
      container = archive.find_entry("META-INF/container.xml")
      unless container && container.size <= MAX_CONTAINER_SIZE
        raise ConversionError, "The .mxl file is missing a valid container."
      end

      container_xml = read_zip_entry(container, MAX_CONTAINER_SIZE)
      container_document = parse_xml(container_xml, error_message: "The .mxl file has an invalid container.")
      musicxml_path = container_document.at_xpath("//*[local-name()='rootfile']")&.[]("full-path")
      unless safe_zip_path?(musicxml_path)
        raise ConversionError, "The .mxl file has an invalid score path."
      end

      musicxml_entry = archive.find_entry(musicxml_path)
      unless musicxml_entry && musicxml_entry.size <= MAX_FILE_SIZE
        raise ConversionError, "The .mxl file does not contain a MusicXML score."
      end

      musicxml = read_zip_entry(musicxml_entry, MAX_FILE_SIZE)
    end
    musicxml
  rescue Zip::Error
    raise ConversionError, "The uploaded .mxl file is not a valid archive."
  end

  def safe_zip_path?(path)
    path.present? &&
      !path.start_with?("/", "\\") &&
      !path.include?("\\") &&
      !path.split("/").include?("..") &&
      !path.include?("\0")
  end

  def read_zip_entry(entry, max_size)
    content = entry.get_input_stream { |stream| stream.read(max_size + 1) }
    raise ConversionError, "An .mxl archive entry exceeds its size limit." if content.bytesize > max_size

    content
  end

  def read_upload
    @upload.tempfile.rewind
    content = @upload.tempfile.read(MAX_FILE_SIZE + 1)
    raise ConversionError, "The uploaded file must be 20 MB or smaller." if content.bytesize > MAX_FILE_SIZE

    content
  ensure
    @upload.tempfile.rewind
  end

  def parse_xml(xml, error_message: "The uploaded file is not valid MusicXML.")
    document = Nokogiri::XML(xml) { |config| config.strict.nonet }
    validate_document_type!(document)

    document
  rescue Nokogiri::XML::SyntaxError
    raise ConversionError, error_message
  end

  def validate_document_type!(document)
    dtd = document.internal_subset
    return unless dtd

    raise ConversionError, "XML entity declarations are not supported." if dtd.entities.present?

    dtd.remove
  end

  def validate_score!(document)
    unless document.root&.name == "score-partwise" && document.at_xpath("//*[local-name()='part']")
      raise ConversionError, "The file must contain a partwise MusicXML score."
    end
  end

  def remove_fingering_annotations(document)
    document.xpath("//*[local-name()='fingering']").remove
  end

  def add_score_metadata(document)
    add_work_title(document.root) if @title
    add_composer(document.root) if @composer
  end

  def add_source_pdf_content(root)
    return if @source_metadata.blank? && @source_page_texts.blank?

    identification = root.at_xpath("./*[local-name()='identification']")
    unless identification
      identification = new_musicxml_node("identification", root)
      following_element = root.at_xpath("./*[local-name()='defaults' or local-name()='credit' or local-name()='part-list']")
      following_element ? following_element.add_previous_sibling(identification) : root.add_child(identification)
    end

    miscellaneous = identification.at_xpath("./*[local-name()='miscellaneous']")
    unless miscellaneous
      miscellaneous = new_musicxml_node("miscellaneous", identification)
      identification.add_child(miscellaneous)
    end

    @source_metadata.each do |key, value|
      add_source_field(miscellaneous, "source-pdf-info-#{key.to_s.parameterize}", value)
    end
    @source_page_texts.each_with_index do |text, index|
      add_source_field(miscellaneous, "source-pdf-page-#{index + 1}-text", text)
    end
  end

  def add_source_field(miscellaneous, name, value)
    return if value.blank?

    field = miscellaneous.element_children.find do |node|
      node.name == "miscellaneous-field" && node["name"] == name
    end
    field ||= new_musicxml_node("miscellaneous-field", miscellaneous).tap do |node|
      node["name"] = name
      miscellaneous.add_child(node)
    end
    field.content = value
  end

  def add_work_title(root)
    work_title = root.at_xpath("./*[local-name()='work']/*[local-name()='work-title']")
    movement_title = root.at_xpath("./*[local-name()='movement-title']")
    titles = [ work_title, movement_title ].compact
    meaningful_title = titles.find { |title| meaningful_title?(title.text) }
    if meaningful_title
      titles.each { |title| title.content = meaningful_title.text unless meaningful_title?(title.text) }
      return
    end

    title_node = titles.first
    unless title_node
      work = new_musicxml_node("work", root)
      first_element = root.element_children.first
      first_element ? first_element.add_previous_sibling(work) : root.add_child(work)
      title_node = new_musicxml_node("work-title", root)
      work.add_child(title_node)
    end
    title_node.content = @title
  end

  def add_composer(root)
    identification = root.at_xpath("./*[local-name()='identification']")
    unless identification
      identification = new_musicxml_node("identification", root)
      following_element = root.at_xpath("./*[local-name()='defaults' or local-name()='credit' or local-name()='part-list']")
      following_element ? following_element.add_previous_sibling(identification) : root.add_child(identification)
    end

    creator = identification.at_xpath("./*[local-name()='creator' and @type='composer']")
    return if creator && creator.text.present? && !placeholder_composer?(creator.text)

    unless creator
      creator = new_musicxml_node("creator", root)
      creator["type"] = "composer"
      first_element = identification.element_children.first
      first_element ? first_element.add_previous_sibling(creator) : identification.add_child(creator)
    end
    creator.content = @composer
  end

  def meaningful_title?(title)
    title.present? && !title.match?(/\A(?:untitled(?:\s+score)?|unknown)\z/i)
  end

  def placeholder_composer?(composer)
    composer.match?(/\A(?:unknown|untitled)\z/i)
  end

  def new_musicxml_node(name, parent)
    Nokogiri::XML::Node.new(name, parent.document).tap { |node| node.namespace = parent.namespace }
  end
end
