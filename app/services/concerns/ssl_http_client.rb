require "net/http"

# Shared HTTP helper that handles the SSL CRL verification issue
# present on some systems where Ruby's OpenSSL rejects certificates
# with unavailable Certificate Revocation Lists.
module SslHttpClient
  private

  def ssl_http(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_callback = ->(_preverify_ok, store_ctx) {
      return true if store_ctx.error == 0
      return true if store_ctx.error == OpenSSL::X509::V_ERR_UNABLE_TO_GET_CRL
      false
    }
    http.open_timeout = 10
    http.read_timeout = 10
    http
  end
end
