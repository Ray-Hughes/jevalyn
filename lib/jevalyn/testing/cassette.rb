# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"

module Jevalyn
  module Testing
    # Records real evaluations to a JSON file and replays them afterwards, so a suite
    # pays for each distinct request once instead of on every run.
    #
    #   Jevalyn::Testing::Cassette.use("spec/cassettes/triage.json") do
    #     SupportTriage.evaluate(ticket.body)
    #   end
    #
    # First run with a real API key recorded; every run after that replays. Delete the
    # file to re-record. Requests are keyed by a digest of the exact body sent, so
    # changing a rubric misses the cassette rather than silently replaying stale answers.
    class Cassette
      attr_reader :path

      def initialize(path)
        @path = path.to_s
        @entries = load_entries
        @recorded = false
      end

      # Runs the block with this cassette installed.
      def self.use(path, &)
        cassette = new(path)
        cassette.install(&)
      end

      def install
        previous = Thread.current[:jevalyn_testing]&.[](:cassette)
        store[:cassette] = self
        yield self
      ensure
        store[:cassette] = previous
        save if @recorded
      end

      # Returns a recorded response for this request body, or nil.
      def fetch(body)
        @entries[digest_for(body)]
      end

      def record(body, response)
        @entries[digest_for(body)] = response
        @recorded = true
        response
      end

      def recorded? = @recorded

      def size = @entries.size

      def save
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "#{JSON.pretty_generate(@entries)}\n")
        @recorded = false
        path
      end

      # A stable key for a request. Sorting keys first means a Hash built in a
      # different order still hits the same entry.
      def digest_for(body)
        Digest::SHA256.hexdigest(JSON.generate(deep_sort(body)))[0, 32]
      end

      private

      def deep_sort(value)
        case value
        when Hash  then value.sort_by { |key, _| key.to_s }.to_h { |k, v| [k.to_s, deep_sort(v)] }
        when Array then value.map { |item| deep_sort(item) }
        else value
        end
      end

      def load_entries
        return {} unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise Error, "Cassette #{path} is not valid JSON: #{e.message}"
      end

      def store
        Thread.current[:jevalyn_testing] ||= {}
      end
    end
  end
end
