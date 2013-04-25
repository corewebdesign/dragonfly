# encoding: utf-8
require 'base64'
require 'yaml'

module Dragonfly
  module Serializer

    # Exceptions
    class BadString < RuntimeError; end

    extend self # So we can do Serializer.b64_encode, etc.

    def b64_encode(string)
      Base64.encode64(string).tr("\n=",'')
    end

    def b64_decode(string)
      padding_length = string.length % 4
      string = string.tr('~', '/')
      Base64.decode64(string + '=' * padding_length)
    end

    def yaml_encode(object)
      b64_encode(YAML.dump(object))
    end

    def yaml_decode(string, opts={})
      raise BadString, "input is blank" if string.nil? || string.empty?
      YAML.load(b64_decode(string))
    rescue Psych::SyntaxError, ArgumentError => e
      raise BadString, "couldn't decode #{string} - got #{e}"
    end

  end
end
