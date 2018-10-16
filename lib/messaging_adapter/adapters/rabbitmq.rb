# frozen_string_literal: true

require 'bunny'
require 'json'

module MessageBrokerAdapter
  # Adapter implements RabbitMQ Exchange
  class RabbitMQ
    @pub_conn_locker = Mutex.new
    @pub_channel_locker = Mutex.new
    @sub_conn_locker = Mutex.new
    @sub_channel_locker = Mutex.new
    @pub_connection = nil
    @sub_connection = nil

    class << self
      attr_reader :pub_conn_locker
      attr_reader :pub_channel_locker
      attr_reader :sub_conn_locker
      attr_reader :sub_channel_locker
    end

    def self.publish(topic, payload, options = {})
      if options[:direct_to_q] == true
        q = publisher_channel.queue(topic, passive: true)
        q.publish(payload.to_json)
      else
        exchange = publisher_channel.fanout(topic, passive: true)
        exchange.publish(payload.to_json)
      end

      puts '- RMQ: Message published successfully on topic ' \
           "#{topic} [#{payload}]"
    end

    def self.subscribe(queue, options = {})
      q = subscriber_channel.queue(queue, passive: true)
      
      options[:block] ||= options[:block].nil? ? true : options[:block]
      q.subscribe(block: options[:block]) do |delivery_info, _properties, payload|
        yield(payload)
      end

      puts "- RMQ: Subscribed successfully to the topic #{queue}"
    end

    def self.connection_configs
      {
        host: ENV['MessageBroker_Host'] || 'localhost',
        port: ENV['MessageBroker_Port'] || '5672',
        username: ENV['MessageBroker_User'] || 'guest',
        password: ENV['MessageBroker_Pass'] || 'guest',
        vhost: ENV['MessageBroker_RabbitMQ_Vhost'] || '/'
      }
    end

    def self.recover_connection(conn, locker)
      locker.synchronize { conn.start } unless conn.open?
    end

    def self.publisher_connection
      if @pub_connection.nil?
        pub_conn_locker.synchronize do
          @pub_connection ||= Bunny.new(connection_configs).tap(&:start)
        end
      else
        recover_connection(@pub_connection, pub_conn_locker)
        @pub_connection
      end
    end

    def self.publisher_channel
      if Thread.current[:rmq_pub_channel].nil?
        pub_channel_locker.synchronize do
          Thread.current[:rmq_pub_channel] ||= publisher_connection.create_channel
        end
      else
        Thread.current[:rmq_pub_channel]
      end
    end

    def self.subscriber_connection
      if @sub_connection.nil?
        sub_conn_locker.synchronize do
          @sub_connection ||= Bunny.new(connection_configs).tap(&:start)
        end
      else
        recover_connection(@sub_connection, sub_conn_locker)
        @sub_connection
      end
    end

    def self.subscriber_channel
      if Thread.current[:rmq_sub_channel].nil?
        sub_channel_locker.synchronize do
          Thread.current[:rmq_sub_channel] ||= subscriber_connection.create_channel
        end
      else
        Thread.current[:rmq_sub_channel]
      end
    end
  end
end
