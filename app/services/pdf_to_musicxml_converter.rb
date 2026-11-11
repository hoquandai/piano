require "fileutils"
require "open3"
require "tmpdir"
require "timeout"

class PdfToMusicxmlConverter
  MAX_PDF_SIZE = 20 * 1024 * 1024
  TIMEOUT_SECONDS = 300

  class ConversionError < StandardError; end

  def initialize(upload)
    @upload = upload
  end

  def call
    validate_upload!

    Dir.mktmpdir("pdf-to-musicxml") do |working_directory|
      input_path = File.join(working_directory, "score.pdf")
      output_directory = File.join(working_directory, "output")
      FileUtils.mkdir_p(output_directory)
      copy_upload(input_path)

      status = run_audiveris(input_path, output_directory)
      raise ConversionError, "Audiveris could not recognize this PDF." unless status.success?

      musicxml_path = Dir.glob(File.join(output_directory, "*.mxl")).first
      raise ConversionError, "Audiveris did not produce a MusicXML file." unless musicxml_path

      File.binread(musicxml_path)
    end
  rescue Errno::ENOENT
    raise ConversionError, "Audiveris is not installed. Rebuild the application Docker image and try again."
  end

  private

  def validate_upload!
    unless @upload.is_a?(ActionDispatch::Http::UploadedFile)
      raise ConversionError, "Choose a PDF file to convert."
    end

    unless @upload.original_filename.to_s.downcase.end_with?(".pdf")
      raise ConversionError, "The uploaded file must have a .pdf extension."
    end

    if @upload.size.zero?
      raise ConversionError, "The uploaded PDF is empty."
    end

    if @upload.size > MAX_PDF_SIZE
      raise ConversionError, "The uploaded PDF must be 20 MB or smaller."
    end

    @upload.tempfile.rewind
    pdf_header = @upload.tempfile.read(5)
    @upload.tempfile.rewind
    raise ConversionError, "The uploaded file is not a valid PDF." unless pdf_header == "%PDF-"
  end

  def copy_upload(input_path)
    @upload.tempfile.rewind
    File.open(input_path, "wb") do |destination|
      IO.copy_stream(@upload.tempfile, destination)
    end
  ensure
    @upload.tempfile.rewind
  end

  def run_audiveris(input_path, output_directory)
    command = [
      ENV.fetch("AUDIVERIS_COMMAND", "audiveris"),
      "-batch",
      "-export",
      "-output",
      output_directory,
      "--",
      input_path
    ]

    Open3.popen3(*command, pgroup: true) do |stdin, stdout, stderr, process|
      stdin.close
      output_readers = [stdout, stderr].map { |stream| Thread.new { stream.read } }

      begin
        Timeout.timeout(TIMEOUT_SECONDS) { process.value }
      rescue Timeout::Error
        begin
          Process.kill("TERM", -process.pid)
        rescue Errno::ESRCH
        end

        raise ConversionError, "Conversion timed out. Try a shorter or smaller PDF."
      ensure
        output_readers.each(&:join)
      end
    end
  end
end
