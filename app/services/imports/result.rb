module Imports
  # What an import did, in enough detail to decide whether to run it for real.
  # `unmapped` is the important one: it names every source value we had no
  # target for, so a dry run tells the operator what they must decide BEFORE
  # any rows land.
  class Result
    attr_reader :created, :updated, :skipped, :unmapped, :errors

    def initialize
      @created = Hash.new(0)
      @updated = Hash.new(0)
      @skipped = Hash.new(0)
      @unmapped = Hash.new { |h, k| h[k] = Set.new }
      @errors = []
    end

    def create!(kind) = @created[kind.to_s] += 1
    def update!(kind) = @updated[kind.to_s] += 1
    def skip!(kind)   = @skipped[kind.to_s] += 1
    def unmapped!(field, value) = @unmapped[field.to_s] << value.to_s
    def error!(message) = @errors << message

    def to_h
      {
        created: @created, updated: @updated, skipped: @skipped,
        unmapped: @unmapped.transform_values(&:to_a).reject { |_, v| v.empty? },
        errors: @errors
      }
    end

    def summary
      parts = []
      parts << "created #{@created.map { |k, v| "#{v} #{k}" }.join(', ')}" if @created.any?
      parts << "updated #{@updated.map { |k, v| "#{v} #{k}" }.join(', ')}" if @updated.any?
      parts << "skipped #{@skipped.map { |k, v| "#{v} #{k}" }.join(', ')}" if @skipped.any?
      parts << "#{@errors.size} errors" if @errors.any?
      parts.presence&.join("; ") || "nothing to do"
    end
  end
end
