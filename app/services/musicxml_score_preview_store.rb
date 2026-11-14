require "fileutils"
require "securerandom"

class MusicxmlScorePreviewStore
  LIFETIME = 1.hour
  STORAGE_DIRECTORY = Rails.root.join("tmp", "musicxml_score_previews")
  TOKEN_ID_PATTERN = /\A[0-9a-f]{32}\z/

  class NotFound < StandardError; end

  def self.create(musicxml, original_filename: nil)
    cleanup_expired
    FileUtils.mkdir_p(STORAGE_DIRECTORY, mode: 0o700)

    id = SecureRandom.hex(16)
    basename = timestamped_basename(original_filename)
    File.open(path_for(id), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(musicxml)
    end

    verifier.generate({ id: id, basename: basename }, expires_in: LIFETIME)
  end

  def self.read(token)
    payload = verified_payload(token)
    raise NotFound unless payload

    File.binread(path_for(payload.fetch(:id)))
  rescue Errno::ENOENT
    raise NotFound
  end

  def self.download_basename(token)
    payload = verified_payload(token)
    raise NotFound unless payload

    payload.fetch(:basename)
  end

  def self.delete(token)
    payload = verified_payload(token)
    return unless payload

    path = path_for(payload.fetch(:id))
    File.delete(path) if File.file?(path)
  end

  def self.cleanup_expired
    return unless Dir.exist?(STORAGE_DIRECTORY)

    expiration_time = LIFETIME.ago
    Dir.glob(STORAGE_DIRECTORY.join("*.musicxml")).each do |path|
      begin
        File.delete(path) if File.file?(path) && File.mtime(path) < expiration_time
      rescue Errno::ENOENT
        # Another request may have removed the same expired file.
      end
    end
  end

  def self.verified_payload(token)
    value = verifier.verified(token)
    return unless value.is_a?(Hash)

    payload = value.symbolize_keys
    return unless payload[:id].is_a?(String) && TOKEN_ID_PATTERN.match?(payload[:id])
    return unless payload[:basename].is_a?(String)

    payload
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
  private_class_method :verified_payload

  def self.timestamped_basename(original_filename)
    normalized_filename = original_filename.to_s.tr("\\", "/")
    original_basename = File.basename(normalized_filename, File.extname(normalized_filename))
    safe_basename = original_basename.gsub(/[<>:"\/\\|?*\x00-\x1F]/, "_").strip
    safe_basename = "piano-score" if safe_basename.blank? || safe_basename == "." || safe_basename == ".."

    "#{safe_basename}-#{Time.current.strftime('%Y%m%d-%H%M%S-%6N')}"
  end
  private_class_method :timestamped_basename

  def self.path_for(id)
    STORAGE_DIRECTORY.join("#{id}.musicxml")
  end
  private_class_method :path_for

  def self.verifier
    Rails.application.message_verifier("musicxml-score-preview")
  end
  private_class_method :verifier
end
