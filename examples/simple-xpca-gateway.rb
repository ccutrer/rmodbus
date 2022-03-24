=begin
It's very simple example of implementation XPCA gateway (see http://www.xpca.org)
for communication with TCP ModBus devices
It receives  REST requests (e.g http://127.0.0.1:4567/mb/127.0.0.1/8502/1/coils/6/17 )
and returns data in JSON format addr : data:
{"coils": {
  "6":{
    "value":0,
    "timestamp":"2011-07-12 18:11:03 +0000",
    "quality":"good"
  },
  "7":{
    "value":0,
    "timestamp":"2011-07-12 18:11:03 +0000",
    "quality":"good"
    }
  ...
}

This code requies gems: rmodbus, sinatra and json
2011 (c) Aleksey Timin
=end

require 'rubygems'
require 'rmodbus'
require 'sinatra'
require 'json'

# Launche TCP ModBus server for test
IP = '127.0.0.1'
PORT = 8502

@srv = ModBus::TCPServer.new(PORT, 1)

@srv.holding_registers = Array.new(100) { |i| i = i + 1 }
@srv.input_registers = Array.new(100) { |i| i = i + 1 }
@srv.coils = Array.new(100) { |i| i = 0 }
@srv.discrete_inputs = Array.new(100) { |i| i = 0 }

@srv.start

# Calc a GET request
# @example
# http://127.0.0.1:4567/mb/127.0.0.1/8502/1/coils/6/17
#
# HTTP route: GET http://localhost/mb/:ip/:port/:slave/:dataplace/:firstaddr/:lastaddr
#
# :ip - ip addr of ModBus TCP Server
# :port - port of ModBUs TCP Server
# :slave - id of slave device
# :dataplace - valid values: coils, discrete_inputs, input_registers, holding_registers
# :firstaddr - first addr of registers(contacts)
# :lastaddr - last addr of registers(contacts)
get '/mb/:ip/:port/:slave/:dataplace/:firstaddr/:lastaddr' do
  resp = {}
  begin
    data = []
    ModBus::TCPClient.new(params[:ip].to_s, params[:port].to_i) do |cl|
      cl.with_slave(params[:slave].to_i) do |slave|
        slave.debug = true
        dataplace = slave.send params[:dataplace]
        data = dataplace[params[:firstaddr].to_i..params[:lastaddr].to_i]
      end
    end

    resp = { params[:dataplace] => {} }
    data.each_with_index do |v, i|
      resp[params[:dataplace]][params[:firstaddr].to_i + i] = {
        :value => v,
        :timestamp => Time.now.utc.strftime("%Y-%m-%d %H:%M:%S %z"),
        :quality => "good"
      }
    end
  rescue Exception => e
    resp = { :error => {
      :type => e.class,
      :message => e.message
    } }
  end

  content_type "application/json"
  resp.to_json
end
