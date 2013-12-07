require 'flex_columns'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns performance" do
  include FlexColumns::Helpers::SystemHelpers

  before :each do
    @dh = FlexColumns::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!

    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :wants_email
      end
    end

    @deserializations = [ ]
    @serializations = [ ]

    ds = @deserializations
    s = @serializations

    ActiveSupport::Notifications.subscribe('flex_columns.deserialize') do |name, start, finish, id, payload|
      ds << payload
    end

    ActiveSupport::Notifications.subscribe('flex_columns.serialize') do |name, start, finish, id, payload|
      s << payload
    end
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  it "should fire a notification when deserializing and serializing" do
    user = ::User.new
    user.name = 'User 1'
    user.wants_email = 'foo'

    @serializations.length.should == 0
    user.save!

    @serializations.length.should == 1
    @serializations[0].class.should == Hash
    @serializations[0].keys.sort_by(&:to_s).should == [ :model_class, :model, :column_name ].sort_by(&:to_s)
    @serializations[0][:model_class].should be(::User)
    @serializations[0][:model].should be(user)
    @serializations[0][:column_name].should == :user_attributes

    user_again = ::User.find(user.id)

    @deserializations.length.should == 0
    user_again.wants_email.should == 'foo'
    @deserializations.length.should == 1
    @deserializations[0].class.should == Hash
    @deserializations[0].keys.sort_by(&:to_s).should == [ :model_class, :model, :column_name, :raw_data ].sort_by(&:to_s)
    @deserializations[0][:model_class].should be(::User)
    @deserializations[0][:model].should be(user_again)
    @deserializations[0][:column_name].should == :user_attributes
    @deserializations[0][:raw_data].should == user_again.user_attributes.to_json
  end

  it "should not deserialize columns if they aren't touched" do
    user = ::User.new
    user.name = 'User 1'
    user.wants_email = 'foo'
    user.save!

    user_again = ::User.find(user.id)
    user_again.user_attributes.should be

    @deserializations.length.should == 0
  end

  it "should not deserialize columns to run validations if there aren't any" do
    user = ::User.new
    user.name = 'User 1'
    user.wants_email = 'foo'
    user.save!

    user_again = ::User.find(user.id)
    user_again.user_attributes.should be
    user_again.valid?.should be
    user_again.user_attributes.valid?.should be

    @deserializations.length.should == 0
  end

  it "should deserialize columns to run validations if there are any" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :wants_email, :integer
      end
    end

    user = ::User.new
    user.name = 'User 1'
    user.wants_email = 12345
    user.save!

    user_again = ::User.find(user.id)
    user_again.user_attributes.should be

    @deserializations.length.should == 0

    user_again.valid?.should be
    user_again.user_attributes.valid?.should be

    @deserializations.length.should == 1
  end
end