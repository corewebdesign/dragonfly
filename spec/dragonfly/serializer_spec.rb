# encoding: utf-8
require 'spec_helper'

describe Dragonfly::Serializer do

  include Dragonfly::Serializer

  describe "base 64 encoding/decoding" do
    [
      'a',
      'sdhflasd',
      '/2010/03/01/hello.png',
      '//..',
      'whats/up.egg.frog',
      '£ñçùí;',
      '~'
    ].each do |string|
      it "should encode #{string.inspect} properly with no padding/line break" do
        b64_encode(string).should_not =~ /\n|=/
      end
      it "should correctly encode and decode #{string.inspect} to the same string" do
        str = b64_decode(b64_encode(string))
        str.force_encoding('UTF-8') if str.respond_to?(:force_encoding)
        str.should == string
      end
    end

    describe "b64_decode" do
      it "converts (deprecated) '~' characters to '/' characters" do
        b64_decode('asdf~asdf').should == b64_decode('asdf/asdf')
      end
    end

  end

  ["psych", "syck"].each do |yamler|
    describe "with #{yamler} yamler" do
      before(:all) do
        @default_yamler = YAML::ENGINE.yamler
        YAML::ENGINE.yamler = yamler
      end
      after(:all) do
        YAML::ENGINE.yamler = @default_yamler
      end

      [
        [3,4,5],
        {'wo' => 'there'},
        [{'this' => :should, 'work' => [3, 5.3, nil, {'egg' => false}]}, [], true]
      ].each do |object|
        it "should correctly yaml encode #{object.inspect} properly with no padding/line break" do
          encoded = yaml_encode(object)
          encoded.should be_a(String)
          encoded.should_not =~ /\n|=/
        end
        it "should correctly yaml encode and decode #{object.inspect} to the same object" do
          yaml_decode(yaml_encode(object)).should == object
        end
      end

      describe "yaml_decode" do
        it "should raise an error if the string passed in is empty" do
          expect{ yaml_decode('') }.to raise_error(Dragonfly::Serializer::BadString)
          expect{ yaml_decode(nil) }.to raise_error(Dragonfly::Serializer::BadString)
        end
        it "should raise an error if the string passed in is invalid YAML" do
          input = b64_encode("\tfoo:\nbar")
          expect{ yaml_decode(input) }.to raise_error(Dragonfly::Serializer::BadString)
        end
      end
    end
  end

end
