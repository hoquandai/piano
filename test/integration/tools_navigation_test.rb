require "test_helper"
require "rack/test"
require "tempfile"
require "zip"

class ToolsNavigationTest < ActionDispatch::IntegrationTest
  test "tools is listed next to dashboard and provides score tools" do
    get rui_dashboard_path
    assert_response :success
    assert_select "nav ul > li > a", text: "Tools", href: rui_tools_path

    get rui_tools_path
    assert_response :success
    assert_select "h1", text: "Tools"
    assert_select "form[data-turbo='false'][method=post]"
    assert_select "form[action='#{rui_tools_visualize_path}'] input[type=file][name=score]"
    assert_select "h2", text: "Preview MusicXML score"
  end

  test "conversion requires a PDF upload" do
    post rui_tools_convert_path

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Choose a PDF file to convert/
  end

  test "PDF conversion redirects to a score preview with MusicXML" do
    converted_content = compressed_musicxml
    converter = Object.new
    converter.define_singleton_method(:call) { converted_content }

    converter_factory = PdfToMusicxmlConverter.singleton_class
    original_new = PdfToMusicxmlConverter.method(:new)
    converter_factory.define_method(:new) { |_pdf| converter }
    begin
      post rui_tools_convert_path,
        params: { pdf: uploaded_score("Moonlight Sonata.pdf", pdf_document(title: "Moonlight Sonata", author: "Ludwig van Beethoven",
          page_lines: [ "Moonlight Sonata", "Ludwig van Beethoven" ])) }
    ensure
      converter_factory.define_method(:new, original_new)
    end

    assert_response :redirect
    token = URI.parse(response.location).path.split("/").last
    @preview_tokens ||= []
    @preview_tokens << token

    follow_redirect!
    assert_response :success
    assert_select "h1", text: "Score Preview"

    get rui_tools_score_musicxml_path(token)
    assert_response :success
    score = Nokogiri::XML(response.body)
    assert_equal "Moonlight Sonata", score.at_xpath("//*[local-name()='work-title']")&.text
    assert_equal "Ludwig van Beethoven",
      score.at_xpath("//*[local-name()='creator' and @type='composer']")&.text
    assert_equal "Moonlight Sonata\nLudwig van Beethoven",
      score.at_xpath("//*[local-name()='miscellaneous-field' and @name='source-pdf-page-1-text']")&.text
    assert_equal "Moonlight Sonata",
      score.at_xpath("//*[local-name()='miscellaneous-field' and @name='source-pdf-info-title']")&.text
    refute score.at_xpath("//*[local-name()='fingering']")

    get rui_tools_score_musicxml_path(token)
    assert_response :success
    assert_match(/filename="Moonlight Sonata-\d{8}-\d{6}-\d{6}\.musicxml"/, response.headers["Content-Disposition"])
  end

  test "PDF metadata extractor dereferences metadata and preserves text from every page" do
    upload = uploaded_http_file(
      "score.pdf",
      pdf_document(
        title: "Clair de Lune",
        author: "Claude Debussy",
        page_lines: [ "Clair de Lune", "Claude Debussy", "Andante" ],
        additional_page_lines: [ [ "Movement II", "Adagio" ] ],
        indirect_metadata: true
      )
    )

    metadata = PdfScoreMetadataExtractor.new(upload).call

    assert_equal "Clair de Lune", metadata.fetch(:title)
    assert_equal "Claude Debussy", metadata.fetch(:composer)
    assert_equal "Clair de Lune", metadata.fetch(:source_metadata).fetch("Title")
    assert_equal [
      "Clair de Lune\nClaude Debussy\nAndante",
      "Movement II\nAdagio"
    ], metadata.fetch(:source_page_texts)
  end

  test "PDF metadata extractor falls back to visible text for placeholder PDF info" do
    upload = uploaded_http_file(
      "score.pdf",
      pdf_document(title: "Untitled Score", author: "Unknown", page_lines: [ "Clair de Lune", "Claude Debussy" ])
    )

    metadata = PdfScoreMetadataExtractor.new(upload).call

    assert_equal "Clair de Lune", metadata.fetch(:title)
    assert_equal "Claude Debussy", metadata.fetch(:composer)
  end

  test "MusicXML preview does not add fingering annotations" do
    result = visualize_score("score.musicxml", musicxml_score)

    assert_response :success
    notes = Nokogiri::XML(preview_musicxml(result)).xpath("//*[local-name()='note']")
    refute notes.any? { |note| note.at_xpath(".//*[local-name()='fingering']") }
  end

  test "preview reads compressed MusicXML produced by the converter" do
    result = visualize_score("score.mxl", compressed_musicxml)

    assert_response :success
    notes = Nokogiri::XML(preview_musicxml(result)).xpath("//*[local-name()='note']")
    assert_equal 3, notes.length
    refute notes.any? { |note| note.at_xpath(".//*[local-name()='fingering']") }
  end

  test "score processor reads compressed content without adding fingerings" do
    musicxml = MusicxmlScoreProcessor.from_content(compressed_musicxml, filename: "converted-score.mxl")

    notes = Nokogiri::XML(musicxml).xpath("//*[local-name()='note']")
    assert_equal 3, notes.length
    refute notes.any? { |note| note.at_xpath(".//*[local-name()='fingering']") }
  end

  test "score processor removes existing fingerings and keeps MusicXML namespaces" do
    result = visualize_score("score.musicxml", musicxml_score(first_fingering: "5"))

    assert_response :success
    document = Nokogiri::XML(preview_musicxml(result))
    notes = document.xpath("//*[local-name()='note']")
    fingerings = notes.map { |note| note.at_xpath("./*[local-name()='notations']/*[local-name()='technical']/*[local-name()='fingering']") }
    assert fingerings.all?(&:blank?)
    assert_equal "http://www.musicxml.org/ns/musicxml", document.root.namespace&.href
    assert notes.all? { |note| note.namespace&.href == "http://www.musicxml.org/ns/musicxml" }
  end

  test "visualizer accepts external DTDs without loading or preserving them" do
    result = visualize_score(
      "score.musicxml",
      musicxml_score(doctype: '<!DOCTYPE score-partwise SYSTEM "file:///not-loaded/score.dtd">')
    )

    assert_response :success
    preview_musicxml_content = preview_musicxml(result)
    refute_includes preview_musicxml_content, "<!DOCTYPE"
    refute_includes preview_musicxml_content, "<fingering"
  end

  test "score preview offers MusicXML and PDF downloads" do
    result = visualize_score("score.musicxml", musicxml_score)
    token = preview_token(result)

    get result.fetch("preview_url")
    assert_response :success
    assert_select "h1", text: "Score Preview"
    assert_select "a[href='#{rui_tools_score_musicxml_path(token)}']", text: "Download MusicXML"
    assert_select "button[data-action='score-preview#downloadPdf']", text: "Download PDF"
    assert_match(/data-score-preview-pdf-filename-value="score-\d{8}-\d{6}-\d{6}\.pdf"/, response.body)

    get rui_tools_score_musicxml_path(token)
    assert_response :success
    assert_match(/filename="score-\d{8}-\d{6}-\d{6}\.musicxml"/, response.headers["Content-Disposition"])
    refute_includes response.body, "<fingering"
  end

  test "score preview rejects expired and invalid tokens" do
    verifier = Rails.application.message_verifier("musicxml-score-preview")
    expired_token = verifier.generate("a" * 32, expires_at: 1.second.ago)
    legacy_token = verifier.generate("a" * 32)

    [ "invalid-token", expired_token, legacy_token ].each do |token|
      get rui_tools_score_path(token)
      assert_response :not_found
      assert_includes response.body, "expired or is unavailable"
    end
  end

  test "visualizer rejects internal DTD entity declarations" do
    post rui_tools_visualize_path,
      params: { score: uploaded_score("score.musicxml", musicxml_score(doctype: "<!DOCTYPE score-partwise [<!ENTITY x \"x\">]>")) },
      headers: { "Accept" => "application/json" }

    assert_response :unprocessable_entity
    assert_equal "XML entity declarations are not supported.", response.parsed_body.fetch("error")
  end

  test "visualizer rejects files that are not MusicXML" do
    post rui_tools_visualize_path,
      params: { score: uploaded_score("score.pdf", "%PDF-invalid") },
      headers: { "Accept" => "application/json" }

    assert_response :unprocessable_entity
    assert_equal "Upload an .xml, .musicxml, or .mxl file.", response.parsed_body.fetch("error")
  end

  private

  def uploaded_score(filename, content)
    tempfile = Tempfile.new([ "musicxml-test", File.extname(filename) ])
    tempfile.binmode
    tempfile.write(content)
    tempfile.rewind
    (@upload_tempfiles ||= []) << tempfile

    Rack::Test::UploadedFile.new(
      tempfile.path,
      "application/vnd.recordare.musicxml",
      original_filename: filename
    )
  end

  def uploaded_http_file(filename, content)
    tempfile = Tempfile.new([ "musicxml-test", File.extname(filename) ])
    tempfile.binmode
    tempfile.write(content)
    tempfile.rewind
    (@upload_tempfiles ||= []) << tempfile

    ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: filename,
      type: "application/pdf"
    )
  end

  def visualize_score(filename, content)
    post rui_tools_visualize_path,
      params: { score: uploaded_score(filename, content) },
      headers: { "Accept" => "application/json" }

    result = response.parsed_body
    @preview_tokens ||= []
    @preview_tokens << preview_token(result) if response.status.between?(200, 299)
    result
  end

  def preview_musicxml(result)
    get rui_tools_score_data_path(preview_token(result))
    assert_response :success
    response.body
  end

  def preview_token(result)
    URI.parse(result.fetch("preview_url")).path.split("/").last
  end

  def teardown
    super
    Array(@upload_tempfiles).each(&:close!)
    Array(@preview_tokens).each { |token| MusicxmlScorePreviewStore.delete(token) }
  end

  def compressed_musicxml
    container = <<~XML
      <container><rootfiles><rootfile full-path="score.musicxml" media-type="application/vnd.recordare.musicxml+xml"/></rootfiles></container>
    XML

    buffer = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("META-INF/container.xml")
      zip.write(container)
      zip.put_next_entry("score.musicxml")
      zip.write(musicxml_score)
    end
    buffer.string
  end

  def pdf_document(title:, author:, page_lines:, additional_page_lines: [], indirect_metadata: false)
    escape = ->(value) { value.gsub(/[\\()]/) { |character| "\\#{character}" } }
    page_line_sets = [ page_lines, *additional_page_lines ]
    page_ids = page_line_sets.each_index.map { |index| 4 + index * 2 }
    content_ids = page_ids.map { |page_id| page_id + 1 }
    info_id = 4 + page_line_sets.length * 2
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [#{page_ids.map { |id| "#{id} 0 R" }.join(' ')}] /Count #{page_ids.length} >>",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    ]
    page_line_sets.each_with_index do |lines, index|
      content = +"BT\n/F1 14 Tf\n72 720 Td\n"
      lines.each do |line|
        content << "(#{escape.call(line)}) Tj\n0 -24 Td\n"
      end
      content << "ET\n"
      objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents #{content_ids[index]} 0 R >>"
      objects << "<< /Length #{content.bytesize} >>\nstream\n#{content}endstream"
    end

    info_entries = []
    metadata_objects = []
    { "Title" => title, "Author" => author }.each do |key, value|
      next unless value

      if indirect_metadata
        object_id = info_id + metadata_objects.length + 1
        info_entries << "/#{key} #{object_id} 0 R"
        metadata_objects << "(#{escape.call(value)})"
      else
        info_entries << "/#{key} (#{escape.call(value)})"
      end
    end
    objects << "<< #{info_entries.join(' ')} >>"
    objects.concat(metadata_objects)

    pdf = +"%PDF-1.4\n"
    offsets = objects.each_with_index.map do |object, index|
      offset = pdf.bytesize
      pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n"
      offset
    end
    xref_offset = pdf.bytesize
    pdf << "xref\n0 #{objects.length + 1}\n0000000000 65535 f \n"
    offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
    pdf << "trailer\n<< /Size #{objects.length + 1} /Root 1 0 R /Info #{info_id} 0 R >>\n"
    pdf << "startxref\n#{xref_offset}\n%%EOF\n"
    pdf
  end

  def musicxml_score(first_fingering: nil, doctype: false, pitches: [ %w[C 4], %w[D 4] ], chord: false)
    score_pitches = pitches.dup
    staff_numbers = pitches.map { |_step, octave| octave.to_i < 4 ? 2 : 1 }.uniq
    score_pitches << (staff_numbers == [ 2 ] ? %w[C 4] : %w[C 3]) if staff_numbers.length == 1
    notes = score_pitches.each_with_index.map do |(step, octave), index|
      notations = if first_fingering && index.zero?
        "<notations><technical><fingering>#{first_fingering}</fingering></technical></notations>"
      else
        ""
      end
      chord_marker = chord && index.positive? && index < pitches.length ? "<chord/>" : ""
      staff = octave.to_i < 4 ? 2 : 1
      "<note>#{chord_marker}<pitch><step>#{step}</step><octave>#{octave}</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><staff>#{staff}</staff>#{notations}</note>"
    end
    doctype_declaration = if doctype == true
      '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">'
    elsif doctype
      doctype
    else
      ""
    end

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      #{doctype_declaration}
      <score-partwise version="3.1" xmlns="http://www.musicxml.org/ns/musicxml">
        <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
        <part id="P1"><measure number="1">
          <attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves>
            <clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef>
          </attributes>#{notes.join}
        </measure></part>
      </score-partwise>
    XML
  end
end
