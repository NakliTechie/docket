require "ipaddr"

module Docket
  # SSRF guard for operator-configured outbound URLs (webhooks). Blocks
  # the unambiguous exfiltration vectors — loopback, link-local (incl. the
  # 169.254.169.254 cloud-metadata endpoint), and localhost.
  #
  # Deliberately literal-IP only: we do NOT resolve DNS (no per-request
  # lookup, no test flakiness, no rebinding TOCTOU to reason about). And
  # RFC1918 private ranges are allowed — a sovereign single-tenant
  # deployment may legitimately POST to an internal CRM on its own network.
  module OutboundUrl
    module_function

    BLOCKED_RANGES = [
      IPAddr.new("127.0.0.0/8"),    # IPv4 loopback
      IPAddr.new("::1/128"),        # IPv6 loopback
      IPAddr.new("169.254.0.0/16"), # IPv4 link-local (cloud metadata)
      IPAddr.new("fe80::/10"),      # IPv6 link-local
      IPAddr.new("0.0.0.0/8")       # "this host"
    ].freeze

    BLOCKED_HOSTNAMES = %w[localhost ip6-localhost].freeze

    # Returns a reason string if the host is an unambiguous SSRF target,
    # else nil.
    def blocked_reason(host)
      host = host.to_s.downcase.strip.delete("[]") # strip IPv6 brackets
      return "blocked hostname '#{host}'" if BLOCKED_HOSTNAMES.include?(host)

      ip = begin
        IPAddr.new(host)
      rescue IPAddr::Error
        return nil # a hostname, not a literal IP — allowed (no DNS lookup)
      end
      BLOCKED_RANGES.any? { |range| range.include?(ip) } ? "blocked address '#{host}'" : nil
    end

    def safe?(host)
      blocked_reason(host).nil?
    end
  end
end
