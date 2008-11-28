require File.join(File.dirname(__FILE__), %w[spec_helper])

# in this spec file we are going to test loading and dumping users and user relationships from the database.

include DB


describe DB, 'a user being modified' do
  before(:each) do
    @user = User.new('unit', 'example.org', 'secret')
  end
  
  it "should set its record to dirty" do
    
  end
  
end

