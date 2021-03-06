require 'flex_columns'
require 'flex_columns/helpers/system_helpers'
require 'flex_columns/helpers/exception_helpers'

describe "FlexColumns error handling" do
  include FlexColumns::Helpers::SystemHelpers
  include FlexColumns::Helpers::ExceptionHelpers

  before :each do
    @dh = FlexColumns::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    migrate do
      drop_table :flexcols_spec_users rescue nil
      create_table :flexcols_spec_users do |t|
        t.string :name, :null => false
        t.string :user_attributes, :limit => 100
      end
    end

    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :wants_email
      end
    end

    define_model_class(:UserBackdoor, 'flexcols_spec_users') { }
  end

  after :each do
    migrate do
      drop_table :flexcols_spec_users rescue nil
    end
  end

  it "should return a nice error if JSON parsing fails" do
    user_bd_1 = ::UserBackdoor.new
    user_bd_1.name = 'User 1'
    user_bd_1.user_attributes = "---unparseable json---"
    user_bd_1.save!

    user = ::User.find(user_bd_1.id)

    e = capture_exception(FlexColumns::Errors::UnparseableJsonInDatabaseError) { user.wants_email }
    e.message.should match(/user.*id.*#{user.id}/i)
    e.message.should match(/\-\-\-unparseable json\-\-\-/i)
    e.message.should match(/JSON::ParserError/i)

    e.data_source.should be(user.user_attributes)
    e.raw_string.should == "---unparseable json---"
    e.source_exception.class.should == JSON::ParserError
  end

  it "should return a nice error if the string isn't even a validly-encoded string" do
    user = ::UserBackdoor.new
    user.name = 'User 1'
    user.save!

    user2 = ::User.find(user.id)

    class << user2
      def [](x)
        if x.to_s == "user_attributes"
          out = "abc\xC3\x28def"
          out = out.force_encoding("UTF-8") if out.respond_to?(:force_encoding)
          out
        else
          super(x)
        end
      end
    end

    if "foo".respond_to?(:force_encoding) # do we have Ruby >= 1.9?
      e = capture_exception(FlexColumns::Errors::IncorrectlyEncodedStringInDatabaseError) { user2.wants_email }
      e.message.should match(/user.*id.*#{user2.id}/i)
      e.message.should match(/abc.*def/i)
      e.message.should match(/position 3/i)
      e.message.should match(/c3/i)

      e.data_source.should be(user2.user_attributes)
      e.raw_string.should match(/abc.*def/i)

      invalid_char = ["C3"].pack("H*")
      invalid_char.force_encoding("UTF-8")

      e.invalid_chars_as_array.include?(invalid_char).should be
      e.raw_data_as_array.include?(invalid_char).should be
      e.raw_data_as_array.include?("a").should be
      e.first_bad_position.should == 3
    else
      e = capture_exception(FlexColumns::Errors::UnparseableJsonInDatabaseError) { user2.wants_email }
      e.message.should match(/user.*id.*#{user2.id}/i)
      e.message.should match(/abc.*def/i)
      e.message.should match(/JSON::ParserError/i)

      e.data_source.should be(user2.user_attributes)
      e.raw_string.should match(/abc.*def/i)
    end
  end

  it "should fail before storing if the JSON produced is too long for the column" do
    user = ::User.new
    user.name = 'User 1'
    user.wants_email = 'aaa' * 10000

    e = capture_exception(FlexColumns::Errors::JsonTooLongError) { user.save! }
    e.message.should match(/user_attributes/i)
    e.message.should match(/100/i)
    e.message.should match(/aaa/i)
    e.message.should match(/30[0-9][0-9][0-9]/i)
    e.message.length.should < 1000

    e.data_source.should be(user.user_attributes)
    e.limit.should == 100
    e.json_string.length.should > 30000
  end
end
