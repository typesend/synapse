require File.join(File.dirname(__FILE__), %w[spec_helper])


describe XMPP::Stream, 'a basic stream' do
  before(:each) do
    
  end
  
  it "should be able to open and close a server stream" do
    lambda {
      stream = XMPP::ServerStreamOut.new('malkier.net', 'example.org')
      stream.connect
      stream.close      
    }.should_not raise_error
  end
  
  it "should be able to open and close and client stream" do
    lambda {
      stream = XMPP::ClientStream.new('malkier.net')
      stream.socket = TCPSocket.new('malkier.net', 5222)
      stream.connect
      stream.close
    }.should_not raise_error
  end
  
  it "should not be able to connect to a stream without a port" do
    lambda {
      stream = XMPP::ClientStream.new('malkier.net')
      stream.connect
      stream.close
    }.should raise_error RuntimeError
  end
  
end

