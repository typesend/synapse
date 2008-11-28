require File.join(File.dirname(__FILE__), %w[spec_helper])

include DB

describe User, 'a new synapse user' do
  before(:each) do
    @user = User.new('unit', 'example.org', 'secret')
  end
  
  it "should correctly generate JID" do
    @user.jid.should == 'unit@example.org'
    DB::User.users['unit@example.org'].should == @user
  end
  
  it "should hash the user password and access it correctly" do
    passwd = Digest::MD5.digest('unit:example.org:secret')
    @user.password.should == passwd
  end
  
  it "should raise an error on attempt to create duplicate user" do
    another_user = DB::User.new('test', 'example.net', 'secret')
    lambda {yet_another = DB::User.new('test', 'example.net', 'secret')}.should raise_error DB::DBError
  end
  
  it "should correctly delete an existing user" do
    newuser = DB::User.new('unit', 'example.com', 'secret')
    lambda {DB::User.delete(newuser.jid)}.should_not raise_error
    DB::User.users['unit@example.com'].should == nil
  end
  
  it "should raise error if attempting to delete a nonexistent user" do
    lambda {DB::User.delete('doesnt_exist@example.com')}.should raise_error DB::DBError
    DB::User.users['doesnt_exist@example.com'].should == nil
  end
  
  it "should authenticate an existing user correctly" do
    DB::User.auth('unit@example.org', 'secret', true).should == true
    DB::User.auth('unit@example.org', 'wrong', true).should == false
  end
  
  it "should not authorise a non-existing user" do
    DB::User.auth('doesnt_exist@example.org', 'fake', true).should == false
  end
  
  it "should authenticate correctly using saslpass" do
    saslpass = Digest::MD5.digest('unit:example.org:secret')
    DB::User.auth('unit@example.org', saslpass).should == true
    saslpass = Digest::MD5.digest('doesnt_exist:example.org:fake')
    DB::User.auth('doesnt_exist@example.org', saslpass).should == false
    saslpass = Digest::MD5.digest('unit:example.org:wrong')
    DB::User.auth('unit@example.org', saslpass).should == false
  end
  
  after(:each) do
    User.delete(@user.jid)
  end
  
end

