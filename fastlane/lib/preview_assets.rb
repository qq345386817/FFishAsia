require "fileutils"

module PreviewAssets
  VIDEO_EXTENSIONS = %w[.mp4 .mov .m4v].freeze

  def self.stage_locale(source:, destination:, platform:)
    videos = Dir.children(source).sort.filter_map do |name|
      path = File.join(source, name)
      path if File.file?(path) && VIDEO_EXTENSIONS.include?(File.extname(name).downcase)
    end
    raise ArgumentError, "No preview videos found in #{source}" if videos.empty?

    FileUtils.mkdir_p(destination)
    videos.map do |path|
      name = File.basename(path)
      name = "DESKTOP-#{name}" if platform == "osx" && !name.upcase.include?("DESKTOP")
      target = File.join(destination, name)
      raise ArgumentError, "Duplicate preview upload filename: #{name}" if File.exist?(target)

      FileUtils.cp(path, target)
      target
    end
  end

  def self.valid_desktop_resolution?(width, height)
    width == 1920 && height == 1080
  end
end
