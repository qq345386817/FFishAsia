require "minitest/autorun"
require "json"

class MetadataTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  LOCALES = %w[en-US de-DE ja ko zh-Hans zh-Hant].freeze

  def metadata(platform, locale, field)
    File.read(File.join(ROOT, "metadata_#{platform}", locale, "#{field}.txt"), encoding: "UTF-8").strip
  end

  def test_store_field_limits_and_keyword_separators
    %w[ios osx].product(LOCALES).each do |platform, locale|
      context = "#{platform}/#{locale}"
      assert_operator metadata(platform, locale, "name").length, :<=, 30, context
      assert_operator metadata(platform, locale, "subtitle").length, :<=, 30, context
      assert_operator metadata(platform, locale, "promotional_text").length, :<=, 170, context
      assert_operator metadata(platform, locale, "description").length, :<=, 4000, context
      notes = metadata(platform, locale, "release_notes").lines.reject { |line| line.strip.empty? }
      assert_operator notes.length, :>=, 1, context
      assert_operator notes.length, :<=, 2, context
      keywords = metadata(platform, locale, "keywords")
      assert_operator keywords.length, :<=, 100, context
      # Keep within both limits described in Apple's product-page and field references.
      assert_operator keywords.bytesize, :<=, 100, context
      terms = keywords.split(",", -1)
      refute terms.any?(&:empty?), context
      assert_equal terms.map(&:strip), terms, context
      assert_equal terms.map(&:downcase).uniq.length, terms.length, context
      refute_match(/https?:|\b(?:Seek|ARLOOPA|iNaturalist)\b/i, keywords, context)
    end
  end

  def test_shared_names_and_subtitles_match_across_platforms
    LOCALES.each do |locale|
      %w[name subtitle release_notes].each do |field|
        assert_equal metadata("ios", locale, field), metadata("osx", locale, field), "#{locale}/#{field}"
      end
    end
  end

  def test_mac_does_not_claim_camera_ar
    LOCALES.each do |locale|
      %w[keywords description promotional_text].each do |field|
        refute_match(/\bAR\b|iPhone|iPad/, metadata("osx", locale, field), "#{locale}/#{field}")
      end
    end
  end

  def test_new_ui_strings_are_translated_in_every_app_language
    strings = JSON.parse(File.read(File.join(ROOT, "..", "FFishAsia/Resources/Localizable.xcstrings")))
    keys = %w[action.close catalog.filter.title catalog.filter.all catalog.filter.animated
              catalog.filter.offline empty.catalogFilter.description search.prompt filter.summary]
    keys.product(%w[en de ja ko zh-Hans zh-Hant]).each do |key, locale|
      unit = strings.fetch("strings").fetch(key).fetch("localizations").fetch(locale).fetch("stringUnit")
      assert_equal "translated", unit.fetch("state"), "#{key}/#{locale}"
      refute_empty unit.fetch("value"), "#{key}/#{locale}"
    end
  end
end
