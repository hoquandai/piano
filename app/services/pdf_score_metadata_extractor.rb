require "pdf/reader"

class PdfScoreMetadataExtractor
  COMPOSER_PREFIX = /\A(?:by|composer|author|composed\s+by|music\s+by)\s*:?\s*(.+)\z/i
  TITLE_PREFIX = /\A(?:title|work)\s*:\s*/i

  def initialize(upload)
    @upload = upload
  end

  def call
    @upload.tempfile.rewind
    reader = PDF::Reader.new(@upload.tempfile)
    page_texts = reader.pages.map { |page| normalize_page_text(page.text) }
    lines = page_texts.first.to_s.lines.map { |line| normalize(line) }.compact
    info = reader.info || {}
    source_metadata = info.each_with_object({}) do |(key, value), metadata|
      metadata[key.to_s] = metadata_value(reader, value)
    end.compact
    title = metadata_title(reader, info) || title_from(lines)
    composer = metadata_composer(reader, info) ||
      composer_from(lines) ||
      adjacent_header_line(lines, title)

    { title: title, composer: composer, source_metadata: source_metadata, source_page_texts: page_texts }
  rescue PDF::Reader::Error => error
    Rails.logger.warn("PDF metadata extraction failed (#{error.class}).")
    { title: nil, composer: nil, source_metadata: {}, source_page_texts: [] }
  ensure
    @upload.tempfile.rewind
  end

  private

  def metadata_value(reader, value)
    value = reader.objects.deref(value) if value.is_a?(PDF::Reader::Reference)
    normalize(value)
  end

  def metadata_title(reader, info)
    title = metadata_value(reader, info[:Title] || info["Title"])
    title unless placeholder_title?(title)
  end

  def metadata_composer(reader, info)
    [ metadata_value(reader, info[:Author] || info["Author"]),
      metadata_value(reader, info[:Composer] || info["Composer"]) ].find do |composer|
      composer && !placeholder_composer?(composer)
    end
  end

  def normalize_page_text(text)
    text.lines.map { |line| normalize(line) }.compact.join("\n")
  end

  def title_from(lines)
    title = normalize(lines.first&.sub(TITLE_PREFIX, ""))
    title unless placeholder_title?(title)
  end

  def composer_from(lines)
    lines.each do |line|
      match = COMPOSER_PREFIX.match(line)
      composer = normalize(match[1]) if match
      return composer if composer && !placeholder_composer?(composer)
    end
    nil
  end

  def adjacent_header_line(lines, title)
    title_index = lines.index { |line| line.casecmp?(title.to_s) }
    candidate_index = title_index ? title_index + 1 : 1
    normalize(lines[candidate_index])
  end

  def normalize(value)
    value.to_s.gsub(/\s+/, " ").strip.presence
  end

  def placeholder_title?(title)
    title.blank? || title.match?(/\A(?:untitled(?:\s+score)?|unknown|score)\z/i)
  end

  def placeholder_composer?(composer)
    composer.match?(/\A(?:unknown|untitled)\z/i)
  end
end
