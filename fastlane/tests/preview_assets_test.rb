require "minitest/autorun"
require "tmpdir"
require_relative "../lib/preview_assets"

class PreviewAssetsTest < Minitest::Test
  def with_locale
    Dir.mktmpdir("preview-assets-test-") do |root|
      source = File.join(root, "source")
      destination = File.join(root, "upload", "ko")
      FileUtils.mkdir_p(source)
      yield source, destination
    end
  end

  def test_mac_upload_adds_desktop_tag_without_changing_original
    with_locale do |source, destination|
      original = File.join(source, "00-preview.mov")
      File.binwrite(original, "video bytes")
      File.binwrite(File.join(source, "01-catalog.png"), "screenshot bytes")
      staged = PreviewAssets.stage_locale(source: source, destination: destination, platform: "osx")
      assert_equal ["DESKTOP-00-preview.mov"], staged.map { |path| File.basename(path) }
      assert_equal "video bytes", File.binread(staged.first)
      assert File.file?(original)
      refute File.exist?(File.join(destination, "01-catalog.png"))
    end
  end

  def test_existing_mac_tag_is_not_duplicated
    with_locale do |source, destination|
      File.binwrite(File.join(source, "DESKTOP-00-preview.mov"), "video")
      staged = PreviewAssets.stage_locale(source: source, destination: destination, platform: "osx")
      assert_equal "DESKTOP-00-preview.mov", File.basename(staged.first)
    end
  end

  def test_ios_device_tags_are_preserved
    with_locale do |source, destination|
      names = %w[IPHONE_67-00-preview.mov IPAD_PRO_3GEN_129-00-preview.mov]
      names.each { |name| File.binwrite(File.join(source, name), "video") }
      staged = PreviewAssets.stage_locale(source: source, destination: destination, platform: "ios")
      assert_equal names.sort, staged.map { |path| File.basename(path) }.sort
    end
  end

  def test_empty_locale_cannot_silently_succeed
    with_locale do |source, destination|
      assert_raises(ArgumentError) { PreviewAssets.stage_locale(source: source, destination: destination, platform: "osx") }
    end
  end

  def test_duplicate_upload_names_are_rejected
    with_locale do |source, destination|
      %w[00-preview.mov DESKTOP-00-preview.mov].each { |name| File.binwrite(File.join(source, name), "video") }
      assert_raises(ArgumentError) { PreviewAssets.stage_locale(source: source, destination: destination, platform: "osx") }
    end
  end

  def test_mac_resolution_is_landscape_full_hd
    assert PreviewAssets.valid_desktop_resolution?(1920, 1080)
    refute PreviewAssets.valid_desktop_resolution?(1080, 1920)
    refute PreviewAssets.valid_desktop_resolution?(1280, 720)
    refute PreviewAssets.valid_desktop_resolution?(nil, nil)
  end
end
