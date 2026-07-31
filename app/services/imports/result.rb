module Imports
  # What an import did, in enough detail to decide whether to run it for real.
  # `unmapped` is the important one: it names every source value we had no
  # target for, so a dry run tells the operator what they must decide BEFORE
  # any rows land.
  class Result
    attr_reader :created, :updated, :deleted, :skipped, :unmapped, :errors, :conflicts,
                :processed
    attr_accessor :watermark
    attr_accessor :run_id, :resume_token

    def initialize
      @created = Hash.new(0)
      @updated = Hash.new(0)
      @deleted = Hash.new(0)
      @skipped = Hash.new(0)
      @unmapped = Hash.new { |h, k| h[k] = Set.new }
      @errors = []
      @conflicts = []
      @processed = 0
    end

    def create!(kind) = @created[kind.to_s] += 1
    def update!(kind) = @updated[kind.to_s] += 1
    def delete!(kind) = @deleted[kind.to_s] += 1
    def skip!(kind)   = @skipped[kind.to_s] += 1
    def unmapped!(field, value) = @unmapped[field.to_s] << value.to_s
    def error!(message) = @errors << message
    def process! = @processed += 1

    def drop!(source_type, field)
      unmapped!("dropped.#{source_type}", field)
    end

    def conflict!(details)
      @conflicts << details.stringify_keys
    end

    def observe_watermark(value)
      parsed = value.is_a?(Time) ? value : Time.zone.parse(value.to_s)
      self.watermark = parsed if parsed && (watermark.nil? || parsed > watermark)
    rescue ArgumentError
      nil
    end

    def counts
      {
        "created" => @created.to_h,
        "updated" => @updated.to_h,
        "deleted" => @deleted.to_h,
        "skipped" => @skipped.to_h,
        "processed" => @processed
      }
    end

    def serialized_unmapped
      @unmapped.transform_values { |values| values.to_a.sort }.reject { |_, values| values.empty? }
    end

    def to_h
      {
        created: @created, updated: @updated, deleted: @deleted, skipped: @skipped,
        unmapped: serialized_unmapped,
        errors: @errors, conflicts: @conflicts, processed: @processed,
        watermark: watermark, run_id: run_id, resume_token: resume_token
      }
    end

    def summary
      parts = []
      parts << "created #{@created.map { |k, v| "#{v} #{k}" }.join(', ')}" if @created.any?
      parts << "updated #{@updated.map { |k, v| "#{v} #{k}" }.join(', ')}" if @updated.any?
      parts << "deleted #{@deleted.map { |k, v| "#{v} #{k}" }.join(', ')}" if @deleted.any?
      parts << "skipped #{@skipped.map { |k, v| "#{v} #{k}" }.join(', ')}" if @skipped.any?
      parts << "#{@conflicts.size} conflicts" if @conflicts.any?
      parts << "#{@errors.size} errors" if @errors.any?
      parts.presence&.join("; ") || "nothing to do"
    end
  end
end
