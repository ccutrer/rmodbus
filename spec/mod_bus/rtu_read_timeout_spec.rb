# -*- coding: ascii
# frozen_string_literal: true

describe ModBus::RTU, "read method" do
  # Minimal test harness that includes the RTU module the same way RTUSlave does,
  # so we can exercise the private `read` helper directly.
  let(:harness_class) do
    Class.new do
      include ModBus::RTU

      attr_accessor :read_retry_timeout

      # expose the private method for testing
      public :read
    end
  end

  let(:harness) { harness_class.new }

  # Fake IO object that lets us control read() and wait_readable() behavior
  let(:io) do
    instance_double("IO").tap do |io_double|
      allow(io_double).to receive(:wait_readable).and_return(true)
    end
  end

  describe "normal operation" do
    it "reads the requested number of bytes in one call" do
      expect(io).to receive(:read).with(4).and_return("abcd")
      expect(harness.read(io, 4)).to eq("abcd")
    end

    it "accumulates partial reads" do
      expect(io).to receive(:read).with(4).and_return("ab")
      expect(io).to receive(:read).with(2).and_return("cd")
      expect(harness.read(io, 4)).to eq("abcd")
    end
  end

  describe "EOF handling" do
    it "raises IOError when read returns nil" do
      expect(io).to receive(:read).with(4).and_return(nil)
      expect { harness.read(io, 4) }.to raise_error(IOError, /End of file/)
    end

    it "raises IOError when read returns nil after partial data" do
      expect(io).to receive(:read).with(4).and_return("ab")
      expect(io).to receive(:read).with(2).and_return(nil)
      expect { harness.read(io, 4) }.to raise_error(IOError, /End of file/)
    end
  end

  describe "timeout on wait_readable" do
    it "raises ModBusTimeout when wait_readable returns nil (timed out)" do
      harness.read_retry_timeout = 0.1

      expect(io).to receive(:read).with(4).and_return("ab")
      expect(io).to receive(:wait_readable).with(0.1).and_return(nil)

      expect { harness.read(io, 4) }.to raise_error(
        ModBus::Errors::ModBusTimeout, /Timeout waiting for serial data/
      )
    end

    it "passes read_retry_timeout to wait_readable" do
      harness.read_retry_timeout = 5

      expect(io).to receive(:read).with(2).and_return("a")
      expect(io).to receive(:wait_readable).with(5).and_return(true)
      expect(io).to receive(:read).with(1).and_return("b")

      expect(harness.read(io, 2)).to eq("ab")
    end

    it "passes nil timeout when read_retry_timeout is not available" do
      # Use a plain object without read_retry_timeout
      plain_harness = Class.new { include ModBus::RTU; public :read }.new

      expect(io).to receive(:read).with(2).and_return("a")
      expect(io).to receive(:wait_readable).with(nil).and_return(true)
      expect(io).to receive(:read).with(1).and_return("b")

      expect(plain_harness.read(io, 2)).to eq("ab")
    end
  end
end

describe ModBus::RTUSlave, "read_pdu deadline" do
  # Build an RTUSlave directly to avoid needing the CCutrer::SerialPort
  # native extension that RTUClient.new requires.
  before do
    @sp = double("SerialPort")
    allow(@sp).to receive(:flush)
    allow(@sp).to receive(:write)

    @slave = ModBus::RTUSlave.new(1, @sp)
    @slave.read_retries = 1
    @slave.read_retry_timeout = 0.3
  end

  it "raises ModBusTimeout on UID mismatch without blocking forever" do
    request = "\x3\x0\x1\x0\x1"
    # Return a valid frame but with wrong UID (0x02 instead of 0x01)
    expect(@sp).to receive(:read).with(2).and_return("\x02\x03")
    expect(@sp).to receive(:read).with(1).and_return("\x02")
    expect(@sp).to receive(:read).with(4).and_return("\xff\xff\xb8\x44")

    started = Time.now
    expect { @slave.query(request) }.to raise_error(ModBus::Errors::ModBusTimeout)
    elapsed = Time.now - started

    # Should complete within a reasonable multiple of read_retry_timeout,
    # not hang forever
    expect(elapsed).to be < 5
  end

  it "raises ModBusTimeout on CRC mismatch without blocking forever" do
    request = "\x3\x0\x1\x0\x1"
    # Return a frame with correct UID but bad CRC
    expect(@sp).to receive(:read).with(2).and_return("\x01\x03")
    expect(@sp).to receive(:read).with(1).and_return("\x02")
    expect(@sp).to receive(:read).with(4).and_return("\xff\xff\x00\x00")

    started = Time.now
    expect { @slave.query(request) }.to raise_error(ModBus::Errors::ModBusTimeout)
    elapsed = Time.now - started

    expect(elapsed).to be < 5
  end
end
