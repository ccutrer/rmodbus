require 'socket'
require 'timeout'

module ModBus
  module TCP
    include Errors
    include Timeout
    attr_reader :ipaddr, :port
    # Open TCP socket
    #
    # @param [String] ipaddr IP address of remote server
    # @param [Integer] port connection port
    # @param [Hash] opts options of connection
    # @option opts [Float, Integer] :connect_timeout seconds timeout for open socket
    # @return [TCPSocket] socket
    #
    # @raise [ModBusTimeout] timed out attempting to create connection
    def open_tcp_connection(ipaddr, port, opts = {})
      @ipaddr, @port = ipaddr, port

      opts[:connect_timeout] ||= 1

      io = nil
      begin
        timeout(opts[:connect_timeout], ModBusTimeout) do
          io = TCPSocket.new(@ipaddr, @port)
        end
      rescue ModBusTimeout => err
        raise ModBusTimeout.new, 'Timed out attempting to create connection'
      end

      io
    end
  end
end
