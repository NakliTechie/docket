require "ipaddr"
require "socket"

module Docket
  # SSRF guard for operator-configured outbound URLs. Validation rejects known
  # unsafe literals/hostnames; delivery resolves once, validates every answer,
  # and pins the connection to a vetted address so DNS cannot change between
  # the check and connect. Sovereign deployments that intentionally deliver to
  # an internal service must explicitly allow its CIDR via
  # DOCKET_OUTBOUND_ALLOW_CIDRS (comma-separated).
  module OutboundUrl
    Blocked = Class.new(StandardError)
    ResolutionError = Class.new(SocketError)

    module_function

    BLOCKED_RANGES = [
      IPAddr.new("0.0.0.0/8"),       # "this host"
      IPAddr.new("10.0.0.0/8"),      # private
      IPAddr.new("100.64.0.0/10"),   # carrier-grade NAT
      IPAddr.new("127.0.0.0/8"),    # IPv4 loopback
      IPAddr.new("169.254.0.0/16"), # IPv4 link-local / cloud metadata
      IPAddr.new("172.16.0.0/12"),  # private
      IPAddr.new("192.168.0.0/16"), # private
      IPAddr.new("198.18.0.0/15"),  # benchmarking
      IPAddr.new("224.0.0.0/4"),    # multicast
      IPAddr.new("240.0.0.0/4"),    # reserved
      IPAddr.new("::/128"),         # unspecified
      IPAddr.new("::1/128"),        # IPv6 loopback
      IPAddr.new("fc00::/7"),       # unique-local
      IPAddr.new("fe80::/10"),      # IPv6 link-local
      IPAddr.new("ff00::/8")        # multicast
    ].freeze

    BLOCKED_HOSTNAMES = %w[localhost ip6-localhost].freeze

    # Fast validation-time check. Hostnames are resolved only immediately
    # before connection by vetted_address, avoiding a validation/connect TOCTOU.
    def blocked_reason(host)
      host = host.to_s.downcase.strip.delete("[]") # strip IPv6 brackets
      if BLOCKED_HOSTNAMES.include?(host) || host.end_with?(".localhost")
        return "blocked hostname '#{host}'"
      end

      ip = parse_ip(host)
      return nil unless ip
      return nil if allowlisted?(ip)

      blocked_ip?(ip) ? "blocked address '#{host}'" : nil
    end

    def safe?(host)
      blocked_reason(host).nil?
    end

    # Resolve once, fail if any answer is unsafe, and return one vetted address
    # for Net::HTTP#ipaddr=. Checking every answer prevents an attacker from
    # hiding a metadata/loopback address behind a public first answer.
    def vetted_address(host, port:)
      if (reason = blocked_reason(host))
        raise Blocked, reason
      end

      addresses = parse_ip(host) ? [ host.to_s.delete("[]") ] : resolve(host, port)
      raise ResolutionError, "no addresses resolved for #{host}" if addresses.empty?

      addresses.each do |address|
        if (reason = blocked_reason(address))
          raise Blocked, "#{host} resolved to #{address}: #{reason}"
        end
      end
      addresses.first
    end

    def resolve(host, port)
      Addrinfo.getaddrinfo(host, port, nil, :STREAM).map(&:ip_address).uniq
    rescue SocketError => e
      raise ResolutionError, "could not resolve #{host}: #{e.message}"
    end

    def parse_ip(value)
      ip = IPAddr.new(value.to_s.delete("[]"))
      ip.ipv4_mapped? ? ip.native : ip
    rescue IPAddr::Error
      nil
    end
    private_class_method :parse_ip

    def blocked_ip?(ip)
      BLOCKED_RANGES.any? { |range| range.include?(ip) }
    end
    private_class_method :blocked_ip?

    def allowlisted?(ip)
      ENV.fetch("DOCKET_OUTBOUND_ALLOW_CIDRS", "").split(",").filter_map do |cidr|
        IPAddr.new(cidr.strip) if cidr.present?
      rescue IPAddr::Error
        nil
      end.any? { |range| range.include?(ip) }
    end
    private_class_method :allowlisted?
  end
end
