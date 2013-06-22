require File.expand_path('../../../load_paths', __FILE__)
require "active_record"
require 'benchmark/ips'

TIME    = (ENV['BENCHMARK_TIME'] || 20).to_i
RECORDS = (ENV['BENCHMARK_RECORDS'] || TIME*1000).to_i

conn = { :adapter => 'sqlite3', :database => ':memory:' }

ActiveRecord::Base.establish_connection(conn)

class User < ActiveRecord::Base
  connection.create_table :users, :force => true do |t|
    t.string :name, :email
    t.timestamps
  end

  has_many :exhibits
end

class Exhibit < ActiveRecord::Base
  connection.create_table :exhibits, :force => true do |t|
    t.belongs_to :user
    t.string :name
    t.text :notes
    t.timestamps
  end

  belongs_to :user

  def look; attributes end
  def feel; look; user.name end

  def self.with_name
    where("name IS NOT NULL")
  end

  def self.with_notes
    where("notes IS NOT NULL")
  end

  def self.look(exhibits) exhibits.each { |e| e.look } end
  def self.feel(exhibits) exhibits.each { |e| e.feel } end
end

puts 'Generating data...'

module ActiveRecord
  class Faker
    LOREM = %Q{Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse non aliquet diam. Curabitur vel urna metus, quis malesuada elit.
     Integer consequat tincidunt felis. Etiam non erat dolor. Vivamus imperdiet nibh sit amet diam eleifend id posuere diam malesuada. Mauris at accumsan sem.
     Donec id lorem neque. Fusce erat lorem, ornare eu congue vitae, malesuada quis neque. Maecenas vel urna a velit pretium fermentum. Donec tortor enim,
     tempor venenatis egestas a, tempor sed ipsum. Ut arcu justo, faucibus non imperdiet ac, interdum at diam. Pellentesque ipsum enim, venenatis ut iaculis vitae,
     varius vitae sem. Sed rutrum quam ac elit euismod bibendum. Donec ultricies ultricies magna, at lacinia libero mollis aliquam. Sed ac arcu in tortor elementum
     tincidunt vel interdum sem. Curabitur eget erat arcu. Praesent eget eros leo. Nam magna enim, sollicitudin vehicula scelerisque in, vulputate ut libero.
     Praesent varius tincidunt commodo}.split

    def self.name
      LOREM.grep(/^\w*$/).sort_by { rand }.first(2).join ' '
    end

    def self.email
      LOREM.grep(/^\w*$/).sort_by { rand }.first(2).join('@') + ".com"
    end
  end
end

# pre-compute the insert statements and fake data compilation,
# so the benchmarks below show the actual runtime for the execute
# method, minus the setup steps

# Using the same paragraph for all exhibits because it is very slow
# to generate unique paragraphs for all exhibits.
notes = ActiveRecord::Faker::LOREM.join ' '
today = Date.today

puts "Inserting #{RECORDS} users and exhibits..."
RECORDS.times do
  user = User.create(
    :created_at => today,
    :name       => ActiveRecord::Faker.name,
    :email      => ActiveRecord::Faker.email
  )

  Exhibit.create(
    :created_at => today,
    :name       => ActiveRecord::Faker.name,
    :user       => user,
    :notes      => notes
  )
end

Benchmark.ips(TIME) do |x|
  ar_obj       = Exhibit.find(1)
  attrs        = { :name => 'sam' }
  attrs_first  = { :name => 'sam' }
  attrs_second = { :name => 'tom' }
  exhibit      = {
    :name       => ActiveRecord::Faker.name,
    :notes      => notes,
    :created_at => Date.today
  }

  x.report("Model#id") do
    ar_obj.id
  end

  x.report 'Model.new (instantiation)' do
    Exhibit.new
  end

  x.report 'Model.new (setting attributes)' do
    Exhibit.new(attrs)
  end

  x.report 'Model.first' do
    Exhibit.first.look
  end

  x.report("Model.all limit(100)") do
    Exhibit.look Exhibit.limit(100)
  end

  x.report "Model.all limit(100) with relationship" do
    Exhibit.feel Exhibit.limit(100).includes(:user)
  end

  x.report "Model.all limit(10,000)" do
    Exhibit.look Exhibit.limit(10000)
  end

  x.report 'Model.named_scope' do
    Exhibit.limit(10).with_name.with_notes
  end

  x.report 'Model.create' do
    Exhibit.create(exhibit)
  end

  x.report 'Resource#attributes=' do
    e = Exhibit.new(attrs_first)
    e.attributes = attrs_second
  end

  x.report 'Resource#update' do
    Exhibit.first.update_attributes(:name => 'bob')
  end

  x.report 'Resource#destroy' do
    Exhibit.first.destroy
  end

  x.report 'Model.transaction' do
    Exhibit.transaction { Exhibit.new }
  end

  x.report 'Model.find(id)' do
    User.find(1)
  end

  x.report 'Model.find_by_sql' do
    Exhibit.find_by_sql("SELECT * FROM exhibits WHERE id = #{(rand * 1000 + 1).to_i}").first
  end

  x.report "Model.log" do
    Exhibit.connection.send(:log, "hello", "world") {}
  end

  x.report "AR.execute(query)" do
    ActiveRecord::Base.connection.execute("Select * from exhibits where id = #{(rand * 1000 + 1).to_i}")
  end
end
$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"
require 'active_record'

class Person < ActiveRecord::Base
  establish_connection :adapter => 'sqlite3', :database => 'foobar.db'
  connection.create_table table_name, :force => true do |t|
    t.string :name
  end
end

bob = Person.create!(:name => 'bob')
puts Person.all.inspect
bob.destroy
puts Person.all.inspect
module ActiveRecord
  # = Active Record Aggregations
  module Aggregations # :nodoc:
    extend ActiveSupport::Concern

    def clear_aggregation_cache #:nodoc:
      @aggregation_cache.clear if persisted?
    end

    # Active Record implements aggregation through a macro-like class method called +composed_of+
    # for representing attributes  as value objects. It expresses relationships like "Account [is]
    # composed of Money [among other things]" or "Person [is] composed of [an] address". Each call
    # to the macro adds a description of how the value objects  are created from the attributes of
    # the entity object (when the entity is initialized either  as a new object or from finding an
    # existing object) and how it can be turned back into attributes  (when the entity is saved to
    # the database).
    #
    #   class Customer < ActiveRecord::Base
    #     composed_of :balance, :class_name => "Money", :mapping => %w(balance amount)
    #     composed_of :address, :mapping => [ %w(address_street street), %w(address_city city) ]
    #   end
    #
    # The customer class now has the following methods to manipulate the value objects:
    # * <tt>Customer#balance, Customer#balance=(money)</tt>
    # * <tt>Customer#address, Customer#address=(address)</tt>
    #
    # These methods will operate with value objects like the ones described below:
    #
    #  class Money
    #    include Comparable
    #    attr_reader :amount, :currency
    #    EXCHANGE_RATES = { "USD_TO_DKK" => 6 }
    #
    #    def initialize(amount, currency = "USD")
    #      @amount, @currency = amount, currency
    #    end
    #
    #    def exchange_to(other_currency)
    #      exchanged_amount = (amount * EXCHANGE_RATES["#{currency}_TO_#{other_currency}"]).floor
    #      Money.new(exchanged_amount, other_currency)
    #    end
    #
    #    def ==(other_money)
    #      amount == other_money.amount && currency == other_money.currency
    #    end
    #
    #    def <=>(other_money)
    #      if currency == other_money.currency
    #        amount <=> other_money.amount
    #      else
    #        amount <=> other_money.exchange_to(currency).amount
    #      end
    #    end
    #  end
    #
    #  class Address
    #    attr_reader :street, :city
    #    def initialize(street, city)
    #      @street, @city = street, city
    #    end
    #
    #    def close_to?(other_address)
    #      city == other_address.city
    #    end
    #
    #    def ==(other_address)
    #      city == other_address.city && street == other_address.street
    #    end
    #  end
    #
    # Now it's possible to access attributes from the database through the value objects instead. If
    # you choose to name the composition the same as the attribute's name, it will be the only way to
    # access that attribute. That's the case with our +balance+ attribute. You interact with the value
    # objects just like you would any other attribute, though:
    #
    #   customer.balance = Money.new(20)     # sets the Money value object and the attribute
    #   customer.balance                     # => Money value object
    #   customer.balance.exchange_to("DKK")  # => Money.new(120, "DKK")
    #   customer.balance > Money.new(10)     # => true
    #   customer.balance == Money.new(20)    # => true
    #   customer.balance < Money.new(5)      # => false
    #
    # Value objects can also be composed of multiple attributes, such as the case of Address. The order
    # of the mappings will determine the order of the parameters.
    #
    #   customer.address_street = "Hyancintvej"
    #   customer.address_city   = "Copenhagen"
    #   customer.address        # => Address.new("Hyancintvej", "Copenhagen")
    #   customer.address = Address.new("May Street", "Chicago")
    #   customer.address_street # => "May Street"
    #   customer.address_city   # => "Chicago"
    #
    # == Writing value objects
    #
    # Value objects are immutable and interchangeable objects that represent a given value, such as
    # a Money object representing $5. Two Money objects both representing $5 should be equal (through
    # methods such as <tt>==</tt> and <tt><=></tt> from Comparable if ranking makes sense). This is
    # unlike entity objects where equality is determined by identity. An entity class such as Customer can
    # easily have two different objects that both have an address on Hyancintvej. Entity identity is
    # determined by object or relational unique identifiers (such as primary keys). Normal
    # ActiveRecord::Base classes are entity objects.
    #
    # It's also important to treat the value objects as immutable. Don't allow the Money object to have
    # its amount changed after creation. Create a new Money object with the new value instead. This
    # is exemplified by the Money#exchange_to method that returns a new value object instead of changing
    # its own values. Active Record won't persist value objects that have been changed through means
    # other than the writer method.
    #
    # The immutable requirement is enforced by Active Record by freezing any object assigned as a value
    # object. Attempting to change it afterwards will result in a ActiveSupport::FrozenObjectError.
    #
    # Read more about value objects on http://c2.com/cgi/wiki?ValueObject and on the dangers of not
    # keeping value objects immutable on http://c2.com/cgi/wiki?ValueObjectsShouldBeImmutable
    #
    # == Custom constructors and converters
    #
    # By default value objects are initialized by calling the <tt>new</tt> constructor of the value
    # class passing each of the mapped attributes, in the order specified by the <tt>:mapping</tt>
    # option, as arguments. If the value class doesn't support this convention then +composed_of+ allows
    # a custom constructor to be specified.
    #
    # When a new value is assigned to the value object the default assumption is that the new value
    # is an instance of the value class. Specifying a custom converter allows the new value to be automatically
    # converted to an instance of value class if necessary.
    #
    # For example, the NetworkResource model has +network_address+ and +cidr_range+ attributes that
    # should be aggregated using the NetAddr::CIDR value class (http://netaddr.rubyforge.org). The constructor
    # for the value class is called +create+ and it expects a CIDR address string as a parameter. New
    # values can be assigned to the value object using either another NetAddr::CIDR object, a string
    # or an array. The <tt>:constructor</tt> and <tt>:converter</tt> options can be used to meet
    # these requirements:
    #
    #   class NetworkResource < ActiveRecord::Base
    #     composed_of :cidr,
    #                 :class_name => 'NetAddr::CIDR',
    #                 :mapping => [ %w(network_address network), %w(cidr_range bits) ],
    #                 :allow_nil => true,
    #                 :constructor => Proc.new { |network_address, cidr_range| NetAddr::CIDR.create("#{network_address}/#{cidr_range}") },
    #                 :converter => Proc.new { |value| NetAddr::CIDR.create(value.is_a?(Array) ? value.join('/') : value) }
    #   end
    #
    #   # This calls the :constructor
    #   network_resource = NetworkResource.new(:network_address => '192.168.0.1', :cidr_range => 24)
    #
    #   # These assignments will both use the :converter
    #   network_resource.cidr = [ '192.168.2.1', 8 ]
    #   network_resource.cidr = '192.168.0.1/24'
    #
    #   # This assignment won't use the :converter as the value is already an instance of the value class
    #   network_resource.cidr = NetAddr::CIDR.create('192.168.2.1/8')
    #
    #   # Saving and then reloading will use the :constructor on reload
    #   network_resource.save
    #   network_resource.reload
    #
    # == Finding records by a value object
    #
    # Once a +composed_of+ relationship is specified for a model, records can be loaded from the database
    # by specifying an instance of the value object in the conditions hash. The following example
    # finds all customers with +balance_amount+ equal to 20 and +balance_currency+ equal to "USD":
    #
    #   Customer.where(:balance => Money.new(20, "USD")).all
    #
    module ClassMethods
      # Adds reader and writer methods for manipulating a value object:
      # <tt>composed_of :address</tt> adds <tt>address</tt> and <tt>address=(new_address)</tt> methods.
      #
      # Options are:
      # * <tt>:class_name</tt> - Specifies the class name of the association. Use it only if that name
      #   can't be inferred from the part id. So <tt>composed_of :address</tt> will by default be linked
      #   to the Address class, but if the real class name is CompanyAddress, you'll have to specify it
      #   with this option.
      # * <tt>:mapping</tt> - Specifies the mapping of entity attributes to attributes of the value
      #   object. Each mapping is represented as an array where the first item is the name of the
      #   entity attribute and the second item is the name of the attribute in the value object. The
      #   order in which mappings are defined determines the order in which attributes are sent to the
      #   value class constructor.
      # * <tt>:allow_nil</tt> - Specifies that the value object will not be instantiated when all mapped
      #   attributes are +nil+. Setting the value object to +nil+ has the effect of writing +nil+ to all
      #   mapped attributes.
      #   This defaults to +false+.
      # * <tt>:constructor</tt> - A symbol specifying the name of the constructor method or a Proc that
      #   is called to initialize the value object. The constructor is passed all of the mapped attributes,
      #   in the order that they are defined in the <tt>:mapping option</tt>, as arguments and uses them
      #   to instantiate a <tt>:class_name</tt> object.
      #   The default is <tt>:new</tt>.
      # * <tt>:converter</tt> - A symbol specifying the name of a class method of <tt>:class_name</tt>
      #   or a Proc that is called when a new value is assigned to the value object. The converter is
      #   passed the single value that is used in the assignment and is only called if the new value is
      #   not an instance of <tt>:class_name</tt>.
      #
      # Option examples:
      #   composed_of :temperature, :mapping => %w(reading celsius)
      #   composed_of :balance, :class_name => "Money", :mapping => %w(balance amount),
      #                         :converter => Proc.new { |balance| balance.to_money }
      #   composed_of :address, :mapping => [ %w(address_street street), %w(address_city city) ]
      #   composed_of :gps_location
      #   composed_of :gps_location, :allow_nil => true
      #   composed_of :ip_address,
      #               :class_name => 'IPAddr',
      #               :mapping => %w(ip to_i),
      #               :constructor => Proc.new { |ip| IPAddr.new(ip, Socket::AF_INET) },
      #               :converter => Proc.new { |ip| ip.is_a?(Integer) ? IPAddr.new(ip, Socket::AF_INET) : IPAddr.new(ip.to_s) }
      #
      def composed_of(part_id, options = {})
        options.assert_valid_keys(:class_name, :mapping, :allow_nil, :constructor, :converter)

        name        = part_id.id2name
        class_name  = options[:class_name]  || name.camelize
        mapping     = options[:mapping]     || [ name, name ]
        mapping     = [ mapping ] unless mapping.first.is_a?(Array)
        allow_nil   = options[:allow_nil]   || false
        constructor = options[:constructor] || :new
        converter   = options[:converter]

        reader_method(name, class_name, mapping, allow_nil, constructor)
        writer_method(name, class_name, mapping, allow_nil, converter)

        create_reflection(:composed_of, part_id, options, self)
      end

      private
        def reader_method(name, class_name, mapping, allow_nil, constructor)
          define_method(name) do
            if @aggregation_cache[name].nil? && (!allow_nil || mapping.any? {|pair| !read_attribute(pair.first).nil? })
              attrs = mapping.collect {|pair| read_attribute(pair.first)}
              object = constructor.respond_to?(:call) ?
                constructor.call(*attrs) :
                class_name.constantize.send(constructor, *attrs)
              @aggregation_cache[name] = object
            end
            @aggregation_cache[name]
          end
        end

        def writer_method(name, class_name, mapping, allow_nil, converter)
          define_method("#{name}=") do |part|
            if part.nil? && allow_nil
              mapping.each { |pair| self[pair.first] = nil }
              @aggregation_cache[name] = nil
            else
              unless part.is_a?(class_name.constantize) || converter.nil?
                part = converter.respond_to?(:call) ?
                  converter.call(part) :
                  class_name.constantize.send(converter, part)
              end

              mapping.each { |pair| self[pair.first] = part.send(pair.last) }
              @aggregation_cache[name] = part.freeze
            end
          end
        end
    end
  end
end
require 'active_support/core_ext/string/conversions'

module ActiveRecord
  module Associations
    # Keeps track of table aliases for ActiveRecord::Associations::ClassMethods::JoinDependency and
    # ActiveRecord::Associations::ThroughAssociationScope
    class AliasTracker # :nodoc:
      attr_reader :aliases, :table_joins, :connection

      # table_joins is an array of arel joins which might conflict with the aliases we assign here
      def initialize(connection = ActiveRecord::Model.connection, table_joins = [])
        @aliases     = Hash.new { |h,k| h[k] = initial_count_for(k) }
        @table_joins = table_joins
        @connection  = connection
      end

      def aliased_table_for(table_name, aliased_name = nil)
        table_alias = aliased_name_for(table_name, aliased_name)

        if table_alias == table_name
          Arel::Table.new(table_name)
        else
          Arel::Table.new(table_name).alias(table_alias)
        end
      end

      def aliased_name_for(table_name, aliased_name = nil)
        aliased_name ||= table_name

        if aliases[table_name].zero?
          # If it's zero, we can have our table_name
          aliases[table_name] = 1
          table_name
        else
          # Otherwise, we need to use an alias
          aliased_name = connection.table_alias_for(aliased_name)

          # Update the count
          aliases[aliased_name] += 1

          if aliases[aliased_name] > 1
            "#{truncate(aliased_name)}_#{aliases[aliased_name]}"
          else
            aliased_name
          end
        end
      end

      private

        def initial_count_for(name)
          return 0 if Arel::Table === table_joins

          # quoted_name should be downcased as some database adapters (Oracle) return quoted name in uppercase
          quoted_name = connection.quote_table_name(name).downcase

          counts = table_joins.map do |join|
            if join.is_a?(Arel::Nodes::StringJoin)
              # Table names + table aliases
              join.left.downcase.scan(
                /join(?:\s+\w+)?\s+(\S+\s+)?#{quoted_name}\son/
              ).size
            else
              join.left.table_name == name ? 1 : 0
            end
          end

          counts.sum
        end

        def truncate(name)
          name.slice(0, connection.table_alias_length - 2)
        end
    end
  end
end
require 'active_support/core_ext/array/wrap'
require 'active_support/core_ext/object/inclusion'

module ActiveRecord
  module Associations
    # = Active Record Associations
    #
    # This is the root class of all associations ('+ Foo' signifies an included module Foo):
    #
    #   Association
    #     SingularAssociation
    #       HasOneAssociation
    #         HasOneThroughAssociation + ThroughAssociation
    #       BelongsToAssociation
    #         BelongsToPolymorphicAssociation
    #     CollectionAssociation
    #       HasAndBelongsToManyAssociation
    #       HasManyAssociation
    #         HasManyThroughAssociation + ThroughAssociation
    class Association #:nodoc:
      attr_reader :owner, :target, :reflection

      delegate :options, :to => :reflection

      def initialize(owner, reflection)
        reflection.check_validity!

        @target = nil
        @owner, @reflection = owner, reflection
        @updated = false

        reset
        reset_scope
      end

      # Returns the name of the table of the related class:
      #
      #   post.comments.aliased_table_name # => "comments"
      #
      def aliased_table_name
        reflection.klass.table_name
      end

      # Resets the \loaded flag to +false+ and sets the \target to +nil+.
      def reset
        @loaded = false
        IdentityMap.remove(target) if IdentityMap.enabled? && target
        @target = nil
      end

      # Reloads the \target and returns +self+ on success.
      def reload
        reset
        reset_scope
        load_target
        self unless target.nil?
      end

      # Has the \target been already \loaded?
      def loaded?
        @loaded
      end

      # Asserts the \target has been loaded setting the \loaded flag to +true+.
      def loaded!
        @loaded      = true
        @stale_state = stale_state
      end

      # The target is stale if the target no longer points to the record(s) that the
      # relevant foreign_key(s) refers to. If stale, the association accessor method
      # on the owner will reload the target. It's up to subclasses to implement the
      # state_state method if relevant.
      #
      # Note that if the target has not been loaded, it is not considered stale.
      def stale_target?
        loaded? && @stale_state != stale_state
      end

      # Sets the target of this association to <tt>\target</tt>, and the \loaded flag to +true+.
      def target=(target)
        @target = target
        loaded!
      end

      def scoped
        target_scope.merge(association_scope)
      end

      # The scope for this association.
      #
      # Note that the association_scope is merged into the target_scope only when the
      # scoped method is called. This is because at that point the call may be surrounded
      # by scope.scoping { ... } or with_scope { ... } etc, which affects the scope which
      # actually gets built.
      def association_scope
        if klass
          @association_scope ||= AssociationScope.new(self).scope
        end
      end

      def reset_scope
        @association_scope = nil
      end

      # Set the inverse association, if possible
      def set_inverse_instance(record)
        if record && invertible_for?(record)
          inverse = record.association(inverse_reflection_for(record).name)
          inverse.target = owner
        end
      end

      # This class of the target. belongs_to polymorphic overrides this to look at the
      # polymorphic_type field on the owner.
      def klass
        reflection.klass
      end

      # Can be overridden (i.e. in ThroughAssociation) to merge in other scopes (i.e. the
      # through association's scope)
      def target_scope
        klass.scoped
      end

      # Loads the \target if needed and returns it.
      #
      # This method is abstract in the sense that it relies on +find_target+,
      # which is expected to be provided by descendants.
      #
      # If the \target is already \loaded it is just returned. Thus, you can call
      # +load_target+ unconditionally to get the \target.
      #
      # ActiveRecord::RecordNotFound is rescued within the method, and it is
      # not reraised. The proxy is \reset and +nil+ is the return value.
      def load_target
        if find_target?
          begin
            if IdentityMap.enabled? && association_class && association_class.respond_to?(:base_class)
              @target = IdentityMap.get(association_class, owner[reflection.foreign_key])
            end
          rescue NameError
            nil
          ensure
            @target ||= find_target
          end
        end
        loaded! unless loaded?
        target
      rescue ActiveRecord::RecordNotFound
        reset
      end

      def interpolate(sql, record = nil)
        if sql.respond_to?(:to_proc)
          owner.send(:instance_exec, record, &sql)
        else
          sql
        end
      end

      private

        def find_target?
          !loaded? && (!owner.new_record? || foreign_key_present?) && klass
        end

        def creation_attributes
          attributes = {}

          if reflection.macro.in?([:has_one, :has_many]) && !options[:through]
            attributes[reflection.foreign_key] = owner[reflection.active_record_primary_key]

            if reflection.options[:as]
              attributes[reflection.type] = owner.class.base_class.name
            end
          end

          attributes
        end

        # Sets the owner attributes on the given record
        def set_owner_attributes(record)
          creation_attributes.each { |key, value| record[key] = value }
        end

        # Should be true if there is a foreign key present on the owner which
        # references the target. This is used to determine whether we can load
        # the target if the owner is currently a new record (and therefore
        # without a key).
        #
        # Currently implemented by belongs_to (vanilla and polymorphic) and
        # has_one/has_many :through associations which go through a belongs_to
        def foreign_key_present?
          false
        end

        # Raises ActiveRecord::AssociationTypeMismatch unless +record+ is of
        # the kind of the class of the associated objects. Meant to be used as
        # a sanity check when you are about to assign an associated record.
        def raise_on_type_mismatch(record)
          unless record.is_a?(reflection.klass) || record.is_a?(reflection.class_name.constantize)
            message = "#{reflection.class_name}(##{reflection.klass.object_id}) expected, got #{record.class}(##{record.class.object_id})"
            raise ActiveRecord::AssociationTypeMismatch, message
          end
        end

        # Can be redefined by subclasses, notably polymorphic belongs_to
        # The record parameter is necessary to support polymorphic inverses as we must check for
        # the association in the specific class of the record.
        def inverse_reflection_for(record)
          reflection.inverse_of
        end

        # Is this association invertible? Can be redefined by subclasses.
        def invertible_for?(record)
          inverse_reflection_for(record)
        end

        # This should be implemented to return the values of the relevant key(s) on the owner,
        # so that when state_state is different from the value stored on the last find_target,
        # the target is stale.
        #
        # This is only relevant to certain associations, which is why it returns nil by default.
        def stale_state
        end

        def association_class
          @reflection.klass
        end

        def build_record(attributes, options)
          reflection.build_association(attributes, options) do |record|
            attributes = create_scope.except(*(record.changed - [reflection.foreign_key]))
            record.assign_attributes(attributes, :without_protection => true)
          end
        end
    end
  end
end
module ActiveRecord
  module Associations
    class AssociationScope #:nodoc:
      include JoinHelper

      attr_reader :association, :alias_tracker

      delegate :klass, :owner, :reflection, :interpolate, :to => :association
      delegate :chain, :conditions, :options, :source_options, :active_record, :to => :reflection

      def initialize(association)
        @association   = association
        @alias_tracker = AliasTracker.new klass.connection
      end

      def scope
        scope = klass.unscoped
        scope = scope.extending(*Array.wrap(options[:extend]))

        # It's okay to just apply all these like this. The options will only be present if the
        # association supports that option; this is enforced by the association builder.
        scope = scope.apply_finder_options(options.slice(
          :readonly, :include, :order, :limit, :joins, :group, :having, :offset, :select))

        if options[:through] && !options[:include]
          scope = scope.includes(source_options[:include])
        end

        scope = scope.uniq if options[:uniq]

        add_constraints(scope)
      end

      private

      def add_constraints(scope)
        tables = construct_tables

        chain.each_with_index do |reflection, i|
          table, foreign_table = tables.shift, tables.first

          if reflection.source_macro == :has_and_belongs_to_many
            join_table = tables.shift

            scope = scope.joins(join(
              join_table,
              table[reflection.association_primary_key].
                eq(join_table[reflection.association_foreign_key])
            ))

            table, foreign_table = join_table, tables.first
          end

          if reflection.source_macro == :belongs_to
            if reflection.options[:polymorphic]
              key = reflection.association_primary_key(klass)
            else
              key = reflection.association_primary_key
            end

            foreign_key = reflection.foreign_key
          else
            key         = reflection.foreign_key
            foreign_key = reflection.active_record_primary_key
          end

          conditions = self.conditions[i]

          if reflection == chain.last
            scope = scope.where(table[key].eq(owner[foreign_key]))

            if reflection.type
              scope = scope.where(table[reflection.type].eq(owner.class.base_class.name))
            end

            conditions.each do |condition|
              if options[:through] && condition.is_a?(Hash)
                condition = disambiguate_condition(table, condition)
              end

              scope = scope.where(interpolate(condition))
            end
          else
            constraint = table[key].eq(foreign_table[foreign_key])

            if reflection.type
              type = chain[i + 1].klass.base_class.name
              constraint = constraint.and(table[reflection.type].eq(type))
            end

            scope = scope.joins(join(foreign_table, constraint))

            unless conditions.empty?
              scope = scope.where(sanitize(conditions, table))
            end
          end
        end

        scope
      end

      def alias_suffix
        reflection.name
      end

      def table_name_for(reflection)
        if reflection == self.reflection
          # If this is a polymorphic belongs_to, we want to get the klass from the
          # association because it depends on the polymorphic_type attribute of
          # the owner
          klass.table_name
        else
          reflection.table_name
        end
      end

      def disambiguate_condition(table, condition)
        if condition.is_a?(Hash)
          Hash[
            condition.map do |k, v|
              if v.is_a?(Hash)
                [k, v]
              else
                [table.table_alias || table.name, { k => v }]
              end
            end
          ]
        else
          condition
        end
      end
    end
  end
end
module ActiveRecord
  # = Active Record Belongs To Associations
  module Associations
    class BelongsToAssociation < SingularAssociation #:nodoc:
      def replace(record)
        raise_on_type_mismatch(record) if record

        update_counters(record)
        replace_keys(record)
        set_inverse_instance(record)

        @updated = true if record

        self.target = record
      end

      def updated?
        @updated
      end

      private

        def find_target?
          !loaded? && foreign_key_present? && klass
        end

        def update_counters(record)
          counter_cache_name = reflection.counter_cache_column

          if counter_cache_name && owner.persisted? && different_target?(record)
            if record
              record.class.increment_counter(counter_cache_name, record.id)
            end

            if foreign_key_present?
              klass.decrement_counter(counter_cache_name, target_id)
            end
          end
        end

        # Checks whether record is different to the current target, without loading it
        def different_target?(record)
          record.nil? && owner[reflection.foreign_key] ||
          record && record.id != owner[reflection.foreign_key]
        end

        def replace_keys(record)
          if record
            owner[reflection.foreign_key] = record[reflection.association_primary_key(record.class)]
          else
            owner[reflection.foreign_key] = nil
          end
        end

        def foreign_key_present?
          owner[reflection.foreign_key]
        end

        # NOTE - for now, we're only supporting inverse setting from belongs_to back onto
        # has_one associations.
        def invertible_for?(record)
          inverse = inverse_reflection_for(record)
          inverse && inverse.macro == :has_one
        end

        def target_id
          if options[:primary_key]
            owner.send(reflection.name).try(:id)
          else
            owner[reflection.foreign_key]
          end
        end

        def stale_state
          owner[reflection.foreign_key].to_s
        end
    end
  end
end
module ActiveRecord
  # = Active Record Belongs To Polymorphic Association
  module Associations
    class BelongsToPolymorphicAssociation < BelongsToAssociation #:nodoc:
      def klass
        type = owner[reflection.foreign_type]
        type.presence && type.constantize
      end

      private

        def replace_keys(record)
          super
          owner[reflection.foreign_type] = record && record.class.base_class.name
        end

        def different_target?(record)
          super || record.class != klass
        end

        def inverse_reflection_for(record)
          reflection.polymorphic_inverse_of(record.class)
        end

        def raise_on_type_mismatch(record)
          # A polymorphic association cannot have a type mismatch, by definition
        end

        def stale_state
          [super, owner[reflection.foreign_type].to_s]
        end
    end
  end
end
module ActiveRecord::Associations::Builder
  class Association #:nodoc:
    class_attribute :valid_options
    self.valid_options = [:class_name, :foreign_key, :select, :conditions, :include, :extend, :readonly, :validate]

    # Set by subclasses
    class_attribute :macro

    attr_reader :model, :name, :options, :reflection

    def self.build(model, name, options)
      new(model, name, options).build
    end

    def initialize(model, name, options)
      @model, @name, @options = model, name, options
    end

    def mixin
      @model.generated_feature_methods
    end

    def build
      validate_options
      reflection = model.create_reflection(self.class.macro, name, options, model)
      define_accessors
      reflection
    end

    private

      def validate_options
        options.assert_valid_keys(self.class.valid_options)
      end

      def define_accessors
        define_readers
        define_writers
      end

      def define_readers
        name = self.name
        mixin.redefine_method(name) do |*params|
          association(name).reader(*params)
        end
      end

      def define_writers
        name = self.name
        mixin.redefine_method("#{name}=") do |value|
          association(name).writer(value)
        end
      end
  end
end
require 'active_support/core_ext/object/inclusion'

module ActiveRecord::Associations::Builder
  class BelongsTo < SingularAssociation #:nodoc:
    self.macro = :belongs_to

    self.valid_options += [:foreign_type, :polymorphic, :touch]

    def constructable?
      !options[:polymorphic]
    end

    def build
      reflection = super
      add_counter_cache_callbacks(reflection) if options[:counter_cache]
      add_touch_callbacks(reflection)         if options[:touch]
      configure_dependency
      reflection
    end

    private

      def add_counter_cache_callbacks(reflection)
        cache_column = reflection.counter_cache_column
        name         = self.name

        method_name = "belongs_to_counter_cache_after_create_for_#{name}"
        mixin.redefine_method(method_name) do
          record = send(name)
          record.class.increment_counter(cache_column, record.id) unless record.nil?
        end
        model.after_create(method_name)

        method_name = "belongs_to_counter_cache_before_destroy_for_#{name}"
        mixin.redefine_method(method_name) do
          record = send(name)
          record.class.decrement_counter(cache_column, record.id) unless record.nil?
        end
        model.before_destroy(method_name)

        model.send(:module_eval,
          "#{reflection.class_name}.send(:attr_readonly,\"#{cache_column}\".intern) if defined?(#{reflection.class_name}) && #{reflection.class_name}.respond_to?(:attr_readonly)", __FILE__, __LINE__
        )
      end

      def add_touch_callbacks(reflection)
        name        = self.name
        method_name = "belongs_to_touch_after_save_or_destroy_for_#{name}"
        touch       = options[:touch]

        mixin.redefine_method(method_name) do
          record = send(name)

          unless record.nil?
            if touch == true
              record.touch
            else
              record.touch(touch)
            end
          end
        end

        model.after_save(method_name)
        model.after_touch(method_name)
        model.after_destroy(method_name)
      end

      def configure_dependency
        if options[:dependent]
          unless options[:dependent].in?([:destroy, :delete])
            raise ArgumentError, "The :dependent option expects either :destroy or :delete (#{options[:dependent].inspect})"
          end

          method_name = "belongs_to_dependent_#{options[:dependent]}_for_#{name}"
          model.send(:class_eval, <<-eoruby, __FILE__, __LINE__ + 1)
            def #{method_name}
              association = #{name}
              association.#{options[:dependent]} if association
            end
          eoruby
          model.after_destroy method_name
        end
      end
  end
end
module ActiveRecord::Associations::Builder
  class CollectionAssociation < Association #:nodoc:
    CALLBACKS = [:before_add, :after_add, :before_remove, :after_remove]

    self.valid_options += [
      :table_name, :order, :group, :having, :limit, :offset, :uniq, :finder_sql,
      :counter_sql, :before_add, :after_add, :before_remove, :after_remove
    ]

    attr_reader :block_extension

    def self.build(model, name, options, &extension)
      new(model, name, options, &extension).build
    end

    def initialize(model, name, options, &extension)
      super(model, name, options)
      @block_extension = extension
    end

    def build
      wrap_block_extension
      reflection = super
      CALLBACKS.each { |callback_name| define_callback(callback_name) }
      reflection
    end

    def writable?
      true
    end

    private

      def wrap_block_extension
        options[:extend] = Array.wrap(options[:extend])

        if block_extension
          silence_warnings do
            model.parent.const_set(extension_module_name, Module.new(&block_extension))
          end
          options[:extend].push("#{model.parent}::#{extension_module_name}".constantize)
        end
      end

      def extension_module_name
        @extension_module_name ||= "#{model.to_s.demodulize}#{name.to_s.camelize}AssociationExtension"
      end

      def define_callback(callback_name)
        full_callback_name = "#{callback_name}_for_#{name}"

        # TODO : why do i need method_defined? I think its because of the inheritance chain
        model.class_attribute full_callback_name.to_sym unless model.method_defined?(full_callback_name)
        model.send("#{full_callback_name}=", Array.wrap(options[callback_name.to_sym]))
      end

      def define_readers
        super

        name = self.name
        mixin.redefine_method("#{name.to_s.singularize}_ids") do
          association(name).ids_reader
        end
      end

      def define_writers
        super

        name = self.name
        mixin.redefine_method("#{name.to_s.singularize}_ids=") do |ids|
          association(name).ids_writer(ids)
        end
      end
  end
end
module ActiveRecord::Associations::Builder
  class HasAndBelongsToMany < CollectionAssociation #:nodoc:
    self.macro = :has_and_belongs_to_many

    self.valid_options += [:join_table, :association_foreign_key, :delete_sql, :insert_sql]

    def build
      reflection = super
      check_validity(reflection)
      define_destroy_hook
      reflection
    end

    private

      def define_destroy_hook
        name = self.name
        model.send(:include, Module.new {
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def destroy_associations
              association(#{name.to_sym.inspect}).delete_all_on_destroy
              super
            end
          RUBY
        })
      end

      # TODO: These checks should probably be moved into the Reflection, and we should not be
      #       redefining the options[:join_table] value - instead we should define a
      #       reflection.join_table method.
      def check_validity(reflection)
        if reflection.association_foreign_key == reflection.foreign_key
          raise ActiveRecord::HasAndBelongsToManyAssociationForeignKeyNeeded.new(reflection)
        end

        reflection.options[:join_table] ||= join_table_name(
          model.send(:undecorated_table_name, model.to_s),
          model.send(:undecorated_table_name, reflection.class_name)
        )
      end

      # Generates a join table name from two provided table names.
      # The names in the join table names end up in lexicographic order.
      #
      #   join_table_name("members", "clubs")         # => "clubs_members"
      #   join_table_name("members", "special_clubs") # => "members_special_clubs"
      def join_table_name(first_table_name, second_table_name)
        if first_table_name < second_table_name
          join_table = "#{first_table_name}_#{second_table_name}"
        else
          join_table = "#{second_table_name}_#{first_table_name}"
        end

        model.table_name_prefix + join_table + model.table_name_suffix
      end
  end
end
require 'active_support/core_ext/object/inclusion'

module ActiveRecord::Associations::Builder
  class HasMany < CollectionAssociation #:nodoc:
    self.macro = :has_many

    self.valid_options += [:primary_key, :dependent, :as, :through, :source, :source_type, :inverse_of]

    def build
      reflection = super
      configure_dependency
      reflection
    end

    private

      def configure_dependency
        if options[:dependent]
          unless options[:dependent].in?([:destroy, :delete_all, :nullify, :restrict])
            raise ArgumentError, "The :dependent option expects either :destroy, :delete_all, " \
                                 ":nullify or :restrict (#{options[:dependent].inspect})"
          end

          send("define_#{options[:dependent]}_dependency_method")
          model.before_destroy dependency_method_name
        end
      end

      def define_destroy_dependency_method
        name = self.name
        mixin.redefine_method(dependency_method_name) do
          send(name).each do |o|
            # No point in executing the counter update since we're going to destroy the parent anyway
            counter_method = ('belongs_to_counter_cache_before_destroy_for_' + self.class.name.downcase).to_sym
            if o.respond_to?(counter_method)
              class << o
                self
              end.send(:define_method, counter_method, Proc.new {})
            end
          end

          send(name).delete_all
        end
      end

      def define_delete_all_dependency_method
        name = self.name
        mixin.redefine_method(dependency_method_name) do
          association(name).delete_all_on_destroy
        end
      end

      def define_nullify_dependency_method
        name = self.name
        mixin.redefine_method(dependency_method_name) do
          send(name).delete_all
        end
      end

      def define_restrict_dependency_method
        name = self.name
        mixin.redefine_method(dependency_method_name) do
          raise ActiveRecord::DeleteRestrictionError.new(name) unless send(name).empty?
        end
      end

      def dependency_method_name
        "has_many_dependent_for_#{name}"
      end
  end
end
require 'active_support/core_ext/object/inclusion'

module ActiveRecord::Associations::Builder
  class HasOne < SingularAssociation #:nodoc:
    self.macro = :has_one

    self.valid_options += [:order, :as]

    class_attribute :through_options
    self.through_options = [:through, :source, :source_type]

    def constructable?
      !options[:through]
    end

    def build
      reflection = super
      configure_dependency unless options[:through]
      reflection
    end

    private

      def validate_options
        valid_options = self.class.valid_options
        valid_options += self.class.through_options if options[:through]
        options.assert_valid_keys(valid_options)
      end

      def configure_dependency
        if options[:dependent]
          unless options[:dependent].in?([:destroy, :delete, :nullify, :restrict])
            raise ArgumentError, "The :dependent option expects either :destroy, :delete, " \
                                 ":nullify or :restrict (#{options[:dependent].inspect})"
          end

          send("define_#{options[:dependent]}_dependency_method")
          model.before_destroy dependency_method_name
        end
      end

      def dependency_method_name
        "has_one_dependent_#{options[:dependent]}_for_#{name}"
      end

      def define_destroy_dependency_method
        name = self.name
        mixin.redefine_method(dependency_method_name) do
          association(name).delete
        end
      end
      alias :define_delete_dependency_method :define_destroy_dependency_method
      alias :define_nullify_dependency_method :define_destroy_dependency_method

      def define_restrict_dependency_method
        name = self.name
        mixin.redefine_method(dependency_method_name) do
          raise ActiveRecord::DeleteRestrictionError.new(name) unless send(name).nil?
        end
      end
  end
end
module ActiveRecord::Associations::Builder
  class SingularAssociation < Association #:nodoc:
    self.valid_options += [:remote, :dependent, :counter_cache, :primary_key, :inverse_of]

    def constructable?
      true
    end

    def define_accessors
      super
      define_constructors if constructable?
    end

    private

      def define_constructors
        name = self.name

        mixin.redefine_method("build_#{name}") do |*params, &block|
          association(name).build(*params, &block)
        end

        mixin.redefine_method("create_#{name}") do |*params, &block|
          association(name).create(*params, &block)
        end

        mixin.redefine_method("create_#{name}!") do |*params, &block|
          association(name).create!(*params, &block)
        end
      end
  end
end
require 'active_support/core_ext/array/wrap'

module ActiveRecord
  module Associations
    # = Active Record Association Collection
    #
    # CollectionAssociation is an abstract class that provides common stuff to
    # ease the implementation of association proxies that represent
    # collections. See the class hierarchy in AssociationProxy.
    #
    # You need to be careful with assumptions regarding the target: The proxy
    # does not fetch records from the database until it needs them, but new
    # ones created with +build+ are added to the target. So, the target may be
    # non-empty and still lack children waiting to be read from the database.
    # If you look directly to the database you cannot assume that's the entire
    # collection because new records may have been added to the target, etc.
    #
    # If you need to work on all current children, new and existing records,
    # +load_target+ and the +loaded+ flag are your friends.
    class CollectionAssociation < Association #:nodoc:
      attr_reader :proxy

      def initialize(owner, reflection)
        super
        @proxy = CollectionProxy.new(self)
      end

      # Implements the reader method, e.g. foo.items for Foo.has_many :items
      def reader(force_reload = false)
        if force_reload
          klass.uncached { reload }
        elsif stale_target?
          reload
        end

        proxy
      end

      # Implements the writer method, e.g. foo.items= for Foo.has_many :items
      def writer(records)
        replace(records)
      end

      # Implements the ids reader method, e.g. foo.item_ids for Foo.has_many :items
      def ids_reader
        if loaded? || options[:finder_sql]
          load_target.map do |record|
            record.send(reflection.association_primary_key)
          end
        else
          column  = "#{reflection.quoted_table_name}.#{reflection.association_primary_key}"
          relation = scoped

          including = (relation.eager_load_values + relation.includes_values).uniq

          if including.any?
            join_dependency = ActiveRecord::Associations::JoinDependency.new(reflection.klass, including, [])
            relation = join_dependency.join_associations.inject(relation) do |r, association|
              association.join_relation(r)
            end
          end

          relation.pluck(column)
        end
      end

      # Implements the ids writer method, e.g. foo.item_ids= for Foo.has_many :items
      def ids_writer(ids)
        pk_column = reflection.primary_key_column
        ids = Array.wrap(ids).reject { |id| id.blank? }
        ids.map! { |i| pk_column.type_cast(i) }
        replace(klass.find(ids).index_by { |r| r.id }.values_at(*ids))
      end

      def reset
        @loaded = false
        @target = []
      end

      def select(select = nil)
        if block_given?
          load_target.select.each { |e| yield e }
        else
          scoped.select(select)
        end
      end

      def find(*args)
        if block_given?
          load_target.find(*args) { |*block_args| yield(*block_args) }
        else
          if options[:finder_sql]
            find_by_scan(*args)
          else
            scoped.find(*args)
          end
        end
      end

      def first(*args)
        first_or_last(:first, *args)
      end

      def last(*args)
        first_or_last(:last, *args)
      end

      def build(attributes = {}, options = {}, &block)
        if attributes.is_a?(Array)
          attributes.collect { |attr| build(attr, options, &block) }
        else
          add_to_target(build_record(attributes, options)) do |record|
            yield(record) if block_given?
          end
        end
      end

      def create(attributes = {}, options = {}, &block)
        create_record(attributes, options, &block)
      end

      def create!(attributes = {}, options = {}, &block)
        create_record(attributes, options, true, &block)
      end

      # Add +records+ to this association. Returns +self+ so method calls may be chained.
      # Since << flattens its argument list and inserts each record, +push+ and +concat+ behave identically.
      def concat(*records)
        load_target if owner.new_record?

        if owner.new_record?
          concat_records(records)
        else
          transaction { concat_records(records) }
        end
      end

      # Starts a transaction in the association class's database connection.
      #
      #   class Author < ActiveRecord::Base
      #     has_many :books
      #   end
      #
      #   Author.first.books.transaction do
      #     # same effect as calling Book.transaction
      #   end
      def transaction(*args)
        reflection.klass.transaction(*args) do
          yield
        end
      end

      # Remove all records from this association
      #
      # See delete for more info.
      def delete_all
        delete(load_target).tap do
          reset
          loaded!
        end
      end

      # Called when the association is declared as :dependent => :delete_all. This is
      # an optimised version which avoids loading the records into memory. Not really
      # for public consumption.
      def delete_all_on_destroy
        scoped.delete_all
      end

      # Destroy all the records from this association.
      #
      # See destroy for more info.
      def destroy_all
        destroy(load_target).tap do
          reset
          loaded!
        end
      end

      # Calculate sum using SQL, not Enumerable
      def sum(*args)
        if block_given?
          scoped.sum(*args) { |*block_args| yield(*block_args) }
        else
          scoped.sum(*args)
        end
      end

      # Count all records using SQL. If the +:counter_sql+ or +:finder_sql+ option is set for the
      # association, it will be used for the query. Otherwise, construct options and pass them with
      # scope to the target class's +count+.
      def count(column_name = nil, count_options = {})
        return 0 if owner.new_record?

        column_name, count_options = nil, column_name if column_name.is_a?(Hash)

        if options[:counter_sql] || options[:finder_sql]
          unless count_options.blank?
            raise ArgumentError, "If finder_sql/counter_sql is used then options cannot be passed"
          end

          reflection.klass.count_by_sql(custom_counter_sql)
        else
          if options[:uniq]
            # This is needed because 'SELECT count(DISTINCT *)..' is not valid SQL.
            column_name ||= reflection.klass.primary_key
            count_options.merge!(:distinct => true)
          end

          value = scoped.count(column_name, count_options)

          limit  = options[:limit]
          offset = options[:offset]

          if limit || offset
            [ [value - offset.to_i, 0].max, limit.to_i ].min
          else
            value
          end
        end
      end

      # Removes +records+ from this association calling +before_remove+ and
      # +after_remove+ callbacks.
      #
      # This method is abstract in the sense that +delete_records+ has to be
      # provided by descendants. Note this method does not imply the records
      # are actually removed from the database, that depends precisely on
      # +delete_records+. They are in any case removed from the collection.
      def delete(*records)
        delete_or_destroy(records, options[:dependent])
      end

      # Destroy +records+ and remove them from this association calling
      # +before_remove+ and +after_remove+ callbacks.
      #
      # Note that this method will _always_ remove records from the database
      # ignoring the +:dependent+ option.
      def destroy(*records)
        records = find(records) if records.any? { |record| record.kind_of?(Fixnum) || record.kind_of?(String) }
        delete_or_destroy(records, :destroy)
      end

      # Returns the size of the collection by executing a SELECT COUNT(*)
      # query if the collection hasn't been loaded, and calling
      # <tt>collection.size</tt> if it has.
      #
      # If the collection has been already loaded +size+ and +length+ are
      # equivalent. If not and you are going to need the records anyway
      # +length+ will take one less query. Otherwise +size+ is more efficient.
      #
      # This method is abstract in the sense that it relies on
      # +count_records+, which is a method descendants have to provide.
      def size
        if !find_target? || (loaded? && !options[:uniq])
          target.size
        elsif !loaded? && options[:group]
          load_target.size
        elsif !loaded? && !options[:uniq] && target.is_a?(Array)
          unsaved_records = target.select { |r| r.new_record? }
          unsaved_records.size + count_records
        else
          count_records
        end
      end

      # Returns the size of the collection calling +size+ on the target.
      #
      # If the collection has been already loaded +length+ and +size+ are
      # equivalent. If not and you are going to need the records anyway this
      # method will take one less query. Otherwise +size+ is more efficient.
      def length
        load_target.size
      end

      # Equivalent to <tt>collection.size.zero?</tt>. If the collection has
      # not been already loaded and you are going to fetch the records anyway
      # it is better to check <tt>collection.length.zero?</tt>.
      def empty?
        size.zero?
      end

      def any?
        if block_given?
          load_target.any? { |*block_args| yield(*block_args) }
        else
          !empty?
        end
      end

      # Returns true if the collection has more than 1 record. Equivalent to collection.size > 1.
      def many?
        if block_given?
          load_target.many? { |*block_args| yield(*block_args) }
        else
          size > 1
        end
      end

      def uniq(collection = load_target)
        seen = {}
        collection.find_all do |record|
          seen[record.id] = true unless seen.key?(record.id)
        end
      end

      # Replace this collection with +other_array+
      # This will perform a diff and delete/add only records that have changed.
      def replace(other_array)
        other_array.each { |val| raise_on_type_mismatch(val) }
        original_target = load_target.dup

        if owner.new_record?
          replace_records(other_array, original_target)
        else
          transaction { replace_records(other_array, original_target) }
        end
      end

      def include?(record)
        if record.is_a?(reflection.klass)
          if record.new_record?
            include_in_memory?(record)
          else
            load_target if options[:finder_sql]
            loaded? ? target.include?(record) : scoped.exists?(record)
          end
        else
          false
        end
      end

      def load_target
        if find_target?
          @target = merge_target_lists(find_target, target)
        end

        loaded!
        target
      end

      def add_to_target(record)
        callback(:before_add, record)
        yield(record) if block_given?

        if options[:uniq] && index = @target.index(record)
          @target[index] = record
        else
          @target << record
        end

        callback(:after_add, record)
        set_inverse_instance(record)

        record
      end

      private

        def custom_counter_sql
          if options[:counter_sql]
            interpolate(options[:counter_sql])
          else
            # replace the SELECT clause with COUNT(SELECTS), preserving any hints within /* ... */
            interpolate(options[:finder_sql]).sub(/SELECT\b(\/\*.*?\*\/ )?(.*)\bFROM\b/im) do
              count_with = $2.to_s
              count_with = '*' if count_with.blank? || count_with =~ /,/ || count_with =~ /\.\*/
              "SELECT #{$1}COUNT(#{count_with}) FROM"
            end
          end
        end

        def custom_finder_sql
          interpolate(options[:finder_sql])
        end

        def find_target
          records =
            if options[:finder_sql]
              reflection.klass.find_by_sql(custom_finder_sql)
            else
              scoped.all
            end

          records = options[:uniq] ? uniq(records) : records
          records.each { |record| set_inverse_instance(record) }
          records
        end

        # We have some records loaded from the database (persisted) and some that are
        # in-memory (memory). The same record may be represented in the persisted array
        # and in the memory array.
        #
        # So the task of this method is to merge them according to the following rules:
        #
        #   * The final array must not have duplicates
        #   * The order of the persisted array is to be preserved
        #   * Any changes made to attributes on objects in the memory array are to be preserved
        #   * Otherwise, attributes should have the value found in the database
        def merge_target_lists(persisted, memory)
          return persisted if memory.empty?
          return memory    if persisted.empty?

          persisted.map! do |record|
            # Unfortunately we cannot simply do memory.delete(record) since on 1.8 this returns
            # record rather than memory.at(memory.index(record)). The behavior is fixed in 1.9.
            mem_index = memory.index(record)

            if mem_index
              mem_record = memory.delete_at(mem_index)

              ((record.attribute_names & mem_record.attribute_names) - mem_record.changes.keys).each do |name|
                mem_record[name] = record[name]
              end

              mem_record
            else
              record
            end
          end

          persisted + memory
        end

        def create_record(attributes, options, raise = false, &block)
          unless owner.persisted?
            raise ActiveRecord::RecordNotSaved, "You cannot call create unless the parent is saved"
          end

          if attributes.is_a?(Array)
            attributes.collect { |attr| create_record(attr, options, raise, &block) }
          else
            transaction do
              add_to_target(build_record(attributes, options)) do |record|
                yield(record) if block_given?
                insert_record(record, true, raise)
              end
            end
          end
        end

        # Do the relevant stuff to insert the given record into the association collection.
        def insert_record(record, validate = true, raise = false)
          raise NotImplementedError
        end

        def create_scope
          scoped.scope_for_create.stringify_keys
        end

        def delete_or_destroy(records, method)
          records = records.flatten
          records.each { |record| raise_on_type_mismatch(record) }
          existing_records = records.reject { |r| r.new_record? }

          if existing_records.empty?
            remove_records(existing_records, records, method)
          else
            transaction { remove_records(existing_records, records, method) }
          end
        end

        def remove_records(existing_records, records, method)
          records.each { |record| callback(:before_remove, record) }

          delete_records(existing_records, method) if existing_records.any?
          records.each { |record| target.delete(record) }

          records.each { |record| callback(:after_remove, record) }
        end

        # Delete the given records from the association, using one of the methods :destroy,
        # :delete_all or :nullify (or nil, in which case a default is used).
        def delete_records(records, method)
          raise NotImplementedError
        end

        def replace_records(new_target, original_target)
          delete(target - new_target)

          unless concat(new_target - target)
            @target = original_target
            raise RecordNotSaved, "Failed to replace #{reflection.name} because one or more of the " \
                                  "new records could not be saved."
          end

          target
        end

        def concat_records(records)
          result = true

          records.flatten.each do |record|
            raise_on_type_mismatch(record)
            add_to_target(record) do |r|
              result &&= insert_record(record) unless owner.new_record?
            end
          end

          result && records
        end

        def callback(method, record)
          callbacks_for(method).each do |callback|
            case callback
            when Symbol
              owner.send(callback, record)
            when Proc
              callback.call(owner, record)
            else
              callback.send(method, owner, record)
            end
          end
        end

        def callbacks_for(callback_name)
          full_callback_name = "#{callback_name}_for_#{reflection.name}"
          owner.class.send(full_callback_name.to_sym) || []
        end

        # Should we deal with assoc.first or assoc.last by issuing an independent query to
        # the database, or by getting the target, and then taking the first/last item from that?
        #
        # If the args is just a non-empty options hash, go to the database.
        #
        # Otherwise, go to the database only if none of the following are true:
        #   * target already loaded
        #   * owner is new record
        #   * custom :finder_sql exists
        #   * target contains new or changed record(s)
        #   * the first arg is an integer (which indicates the number of records to be returned)
        def fetch_first_or_last_using_find?(args)
          if args.first.is_a?(Hash)
            true
          else
            !(loaded? ||
              owner.new_record? ||
              options[:finder_sql] ||
              target.any? { |record| record.new_record? || record.changed? } ||
              args.first.kind_of?(Integer))
          end
        end

        def include_in_memory?(record)
          if reflection.is_a?(ActiveRecord::Reflection::ThroughReflection)
            owner.send(reflection.through_reflection.name).any? { |source|
              target = source.send(reflection.source_reflection.name)
              target.respond_to?(:include?) ? target.include?(record) : target == record
            } || target.include?(record)
          else
            target.include?(record)
          end
        end

        # If using a custom finder_sql, #find scans the entire collection.
        def find_by_scan(*args)
          expects_array = args.first.kind_of?(Array)
          ids           = args.flatten.compact.uniq.map { |arg| arg.to_i }

          if ids.size == 1
            id = ids.first
            record = load_target.detect { |r| id == r.id }
            expects_array ? [ record ] : record
          else
            load_target.select { |r| ids.include?(r.id) }
          end
        end

        # Fetches the first/last using SQL if possible, otherwise from the target array.
        def first_or_last(type, *args)
          args.shift if args.first.is_a?(Hash) && args.first.empty?

          collection = fetch_first_or_last_using_find?(args) ? scoped : load_target
          collection.send(type, *args).tap do |record|
            set_inverse_instance record if record.is_a? ActiveRecord::Base
          end
        end
    end
  end
end
module ActiveRecord
  module Associations
    # Association proxies in Active Record are middlemen between the object that
    # holds the association, known as the <tt>@owner</tt>, and the actual associated
    # object, known as the <tt>@target</tt>. The kind of association any proxy is
    # about is available in <tt>@reflection</tt>. That's an instance of the class
    # ActiveRecord::Reflection::AssociationReflection.
    #
    # For example, given
    #
    #   class Blog < ActiveRecord::Base
    #     has_many :posts
    #   end
    #
    #   blog = Blog.first
    #
    # the association proxy in <tt>blog.posts</tt> has the object in +blog+ as
    # <tt>@owner</tt>, the collection of its posts as <tt>@target</tt>, and
    # the <tt>@reflection</tt> object represents a <tt>:has_many</tt> macro.
    #
    # This class has most of the basic instance methods removed, and delegates
    # unknown methods to <tt>@target</tt> via <tt>method_missing</tt>. As a
    # corner case, it even removes the +class+ method and that's why you get
    #
    #   blog.posts.class # => Array
    #
    # though the object behind <tt>blog.posts</tt> is not an Array, but an
    # ActiveRecord::Associations::HasManyAssociation.
    #
    # The <tt>@target</tt> object is not \loaded until needed. For example,
    #
    #   blog.posts.count
    #
    # is computed directly through SQL and does not trigger by itself the
    # instantiation of the actual post records.
    class CollectionProxy # :nodoc:
      alias :proxy_extend :extend

      instance_methods.each { |m| undef_method m unless m.to_s =~ /^(?:nil\?|send|object_id|to_a)$|^__|^respond_to|proxy_/ }

      delegate :group, :order, :limit, :joins, :where, :preload, :eager_load, :includes, :from,
               :lock, :readonly, :having, :pluck, :to => :scoped

      delegate :target, :load_target, :loaded?, :to => :@association

      delegate :select, :find, :first, :last,
               :build, :create, :create!,
               :concat, :replace, :delete_all, :destroy_all, :delete, :destroy, :uniq,
               :sum, :count, :size, :length, :empty?,
               :any?, :many?, :include?,
               :to => :@association

      def initialize(association)
        @association = association
        Array.wrap(association.options[:extend]).each { |ext| proxy_extend(ext) }
      end

      alias_method :new, :build

      def proxy_association
        @association
      end

      def scoped
        association = @association
        association.scoped.extending do
          define_method(:proxy_association) { association }
        end
      end

      def respond_to?(name, include_private = false)
        super ||
        (load_target && target.respond_to?(name, include_private)) ||
        proxy_association.klass.respond_to?(name, include_private)
      end

      def method_missing(method, *args, &block)
        match = DynamicFinderMatch.match(method)
        if match && match.instantiator?
          send(:find_or_instantiator_by_attributes, match, match.attribute_names, *args) do |r|
            proxy_association.send :set_owner_attributes, r
            proxy_association.send :add_to_target, r
            yield(r) if block_given?
          end

        elsif target.respond_to?(method) || (!proxy_association.klass.respond_to?(method) && Class.respond_to?(method))
          if load_target
            if target.respond_to?(method)
              target.send(method, *args, &block)
            else
              begin
                super
              rescue NoMethodError => e
                raise e, e.message.sub(/ for #<.*$/, " via proxy for #{target}")
              end
            end
          end

        else
          scoped.readonly(nil).send(method, *args, &block)
        end
      end

      # Forwards <tt>===</tt> explicitly to the \target because the instance method
      # removal above doesn't catch it. Loads the \target if needed.
      def ===(other)
        other === load_target
      end

      def to_ary
        load_target.dup
      end
      alias_method :to_a, :to_ary

      def <<(*records)
        proxy_association.concat(records) && self
      end
      alias_method :push, :<<

      def clear
        delete_all
        self
      end

      def reload
        proxy_association.reload
        self
      end
    end
  end
end
module ActiveRecord
  # = Active Record Has And Belongs To Many Association
  module Associations
    class HasAndBelongsToManyAssociation < CollectionAssociation #:nodoc:
      attr_reader :join_table

      def initialize(owner, reflection)
        @join_table = Arel::Table.new(reflection.options[:join_table])
        super
      end

      def insert_record(record, validate = true, raise = false)
        if record.new_record?
          if raise
            record.save!(:validate => validate)
          else
            return unless record.save(:validate => validate)
          end
        end

        if options[:insert_sql]
          owner.connection.insert(interpolate(options[:insert_sql], record))
        else
          stmt = join_table.compile_insert(
            join_table[reflection.foreign_key]             => owner.id,
            join_table[reflection.association_foreign_key] => record.id
          )

          owner.connection.insert stmt
        end

        record
      end

      # ActiveRecord::Relation#delete_all needs to support joins before we can use a
      # SQL-only implementation.
      alias delete_all_on_destroy delete_all

      private

        def count_records
          load_target.size
        end

        def delete_records(records, method)
          if sql = options[:delete_sql]
            records = load_target if records == :all
            records.each { |record| owner.connection.delete(interpolate(sql, record)) }
          else
            relation = join_table
            stmt = relation.where(relation[reflection.foreign_key].eq(owner.id).
              and(relation[reflection.association_foreign_key].in(records.map { |x| x.id }.compact))
            ).compile_delete
            owner.connection.delete stmt
          end
        end

        def invertible_for?(record)
          false
        end
    end
  end
end
module ActiveRecord
  # = Active Record Has Many Association
  module Associations
    # This is the proxy that handles a has many association.
    #
    # If the association has a <tt>:through</tt> option further specialization
    # is provided by its child HasManyThroughAssociation.
    class HasManyAssociation < CollectionAssociation #:nodoc:

      def insert_record(record, validate = true, raise = false)
        set_owner_attributes(record)

        if raise
          record.save!(:validate => validate)
        else
          record.save(:validate => validate)
        end
      end

      private

        # Returns the number of records in this collection.
        #
        # If the association has a counter cache it gets that value. Otherwise
        # it will attempt to do a count via SQL, bounded to <tt>:limit</tt> if
        # there's one. Some configuration options like :group make it impossible
        # to do an SQL count, in those cases the array count will be used.
        #
        # That does not depend on whether the collection has already been loaded
        # or not. The +size+ method is the one that takes the loaded flag into
        # account and delegates to +count_records+ if needed.
        #
        # If the collection is empty the target is set to an empty array and
        # the loaded flag is set to true as well.
        def count_records
          count = if has_cached_counter?
            owner.send(:read_attribute, cached_counter_attribute_name)
          elsif options[:counter_sql] || options[:finder_sql]
            reflection.klass.count_by_sql(custom_counter_sql)
          else
            scoped.count
          end

          # If there's nothing in the database and @target has no new records
          # we are certain the current target is an empty array. This is a
          # documented side-effect of the method that may avoid an extra SELECT.
          @target ||= [] and loaded! if count == 0

          [options[:limit], count].compact.min
        end

        def has_cached_counter?(reflection = reflection)
          owner.attribute_present?(cached_counter_attribute_name(reflection))
        end

        def cached_counter_attribute_name(reflection = reflection)
          "#{reflection.name}_count"
        end

        def update_counter(difference, reflection = reflection)
          if has_cached_counter?(reflection)
            counter = cached_counter_attribute_name(reflection)
            owner.class.update_counters(owner.id, counter => difference)
            owner[counter] += difference
            owner.changed_attributes.delete(counter) # eww
          end
        end

        # This shit is nasty. We need to avoid the following situation:
        #
        #   * An associated record is deleted via record.destroy
        #   * Hence the callbacks run, and they find a belongs_to on the record with a
        #     :counter_cache options which points back at our owner. So they update the
        #     counter cache.
        #   * In which case, we must make sure to *not* update the counter cache, or else
        #     it will be decremented twice.
        #
        # Hence this method.
        def inverse_updates_counter_cache?(reflection = reflection)
          counter_name = cached_counter_attribute_name(reflection)
          reflection.klass.reflect_on_all_associations(:belongs_to).any? { |inverse_reflection|
            inverse_reflection.counter_cache_column == counter_name
          }
        end

        # Deletes the records according to the <tt>:dependent</tt> option.
        def delete_records(records, method)
          if method == :destroy
            records.each { |r| r.destroy }
            update_counter(-records.length) unless inverse_updates_counter_cache?
          else
            keys  = records.map { |r| r[reflection.association_primary_key] }
            scope = scoped.where(reflection.association_primary_key => keys)

            if method == :delete_all
              update_counter(-scope.delete_all)
            else
              update_counter(-scope.update_all(reflection.foreign_key => nil))
            end
          end
        end

        def foreign_key_present?
          owner.attribute_present?(reflection.association_primary_key)
        end
    end
  end
end
require 'active_support/core_ext/object/blank'

module ActiveRecord
  # = Active Record Has Many Through Association
  module Associations
    class HasManyThroughAssociation < HasManyAssociation #:nodoc:
      include ThroughAssociation

      def initialize(owner, reflection)
        super

        @through_records     = {}
        @through_association = nil
      end

      # Returns the size of the collection by executing a SELECT COUNT(*) query if the collection hasn't been
      # loaded and calling collection.size if it has. If it's more likely than not that the collection does
      # have a size larger than zero, and you need to fetch that collection afterwards, it'll take one fewer
      # SELECT query if you use #length.
      def size
        if has_cached_counter?
          owner.send(:read_attribute, cached_counter_attribute_name)
        elsif loaded?
          target.size
        else
          count
        end
      end

      def concat(*records)
        unless owner.new_record?
          records.flatten.each do |record|
            raise_on_type_mismatch(record)
            record.save! if record.new_record?
          end
        end

        super
      end

      def concat_records(records)
        ensure_not_nested

        records = super

        if owner.new_record? && records
          records.flatten.each do |record|
            build_through_record(record)
          end
        end

        records
      end

      def insert_record(record, validate = true, raise = false)
        ensure_not_nested

        if record.new_record?
          if raise
            record.save!(:validate => validate)
          else
            return unless record.save(:validate => validate)
          end
        end

        save_through_record(record)
        update_counter(1)
        record
      end

      # ActiveRecord::Relation#delete_all needs to support joins before we can use a
      # SQL-only implementation.
      alias delete_all_on_destroy delete_all

      private

        def through_association
          @through_association ||= owner.association(through_reflection.name)
        end

        # We temporarily cache through record that has been build, because if we build a
        # through record in build_record and then subsequently call insert_record, then we
        # want to use the exact same object.
        #
        # However, after insert_record has been called, we clear the cache entry because
        # we want it to be possible to have multiple instances of the same record in an
        # association
        def build_through_record(record)
          @through_records[record.object_id] ||= begin
            ensure_mutable

            through_record = through_association.build
            through_record.send("#{source_reflection.name}=", record)
            through_record
          end
        end

        def save_through_record(record)
          build_through_record(record).save!
        ensure
          @through_records.delete(record.object_id)
        end

        def build_record(attributes, options = {})
          ensure_not_nested

          record = super(attributes, options)

          inverse = source_reflection.inverse_of
          if inverse
            if inverse.macro == :has_many
              record.send(inverse.name) << build_through_record(record)
            elsif inverse.macro == :has_one
              record.send("#{inverse.name}=", build_through_record(record))
            end
          end

          record
        end

        def target_reflection_has_associated_record?
          if through_reflection.macro == :belongs_to && owner[through_reflection.foreign_key].blank?
            false
          else
            true
          end
        end

        def update_through_counter?(method)
          case method
          when :destroy
            !inverse_updates_counter_cache?(through_reflection)
          when :nullify
            false
          else
            true
          end
        end

        def delete_records(records, method)
          ensure_not_nested

          scope = through_association.scoped.where(construct_join_attributes(*records))

          case method
          when :destroy
            count = scope.destroy_all.length
          when :nullify
            count = scope.update_all(source_reflection.foreign_key => nil)
          else
            count = scope.delete_all
          end

          delete_through_records(records)

          if through_reflection.macro == :has_many && update_through_counter?(method)
            update_counter(-count, through_reflection)
          end

          update_counter(-count)
        end

        def through_records_for(record)
          attributes = construct_join_attributes(record)
          candidates = Array.wrap(through_association.target)
          candidates.find_all { |c| c.attributes.slice(*attributes.keys) == attributes }
        end

        def delete_through_records(records)
          records.each do |record|
            through_records = through_records_for(record)

            if through_reflection.macro == :has_many
              through_records.each { |r| through_association.target.delete(r) }
            else
              if through_records.include?(through_association.target)
                through_association.target = nil
              end
            end

            @through_records.delete(record.object_id)
          end
        end

        def find_target
          return [] unless target_reflection_has_associated_record?
          scoped.all
        end

        # NOTE - not sure that we can actually cope with inverses here
        def invertible_for?(record)
          false
        end
    end
  end
end
require 'active_support/core_ext/object/inclusion'

module ActiveRecord
  # = Active Record Belongs To Has One Association
  module Associations
    class HasOneAssociation < SingularAssociation #:nodoc:
      def replace(record, save = true)
        raise_on_type_mismatch(record) if record
        load_target

        # If target and record are nil, or target is equal to record,
        # we don't need to have transaction.
        if (target || record) && target != record
          reflection.klass.transaction do
            remove_target!(options[:dependent]) if target && !target.destroyed?
  
            if record
              set_owner_attributes(record)
              set_inverse_instance(record)
  
              if owner.persisted? && save && !record.save
                nullify_owner_attributes(record)
                set_owner_attributes(target) if target
                raise RecordNotSaved, "Failed to save the new associated #{reflection.name}."
              end
            end
          end
        end

        self.target = record
      end

      def delete(method = options[:dependent])
        if load_target
          case method
            when :delete
              target.delete
            when :destroy
              target.destroy
            when :nullify
              target.update_attribute(reflection.foreign_key, nil)
          end
        end
      end

      private

        # The reason that the save param for replace is false, if for create (not just build),
        # is because the setting of the foreign keys is actually handled by the scoping when
        # the record is instantiated, and so they are set straight away and do not need to be
        # updated within replace.
        def set_new_record(record)
          replace(record, false)
        end

        def remove_target!(method)
          if method.in?([:delete, :destroy])
            target.send(method)
          else
            nullify_owner_attributes(target)

            if target.persisted? && owner.persisted? && !target.save
              set_owner_attributes(target)
              raise RecordNotSaved, "Failed to remove the existing associated #{reflection.name}. " +
                                    "The record failed to save when after its foreign key was set to nil."
            end
          end
        end

        def nullify_owner_attributes(record)
          record[reflection.foreign_key] = nil
        end
    end
  end
end
module ActiveRecord
  # = Active Record Has One Through Association
  module Associations
    class HasOneThroughAssociation < HasOneAssociation #:nodoc:
      include ThroughAssociation

      def replace(record)
        create_through_record(record)
        self.target = record
      end

      private

        def create_through_record(record)
          ensure_not_nested

          through_proxy  = owner.association(through_reflection.name)
          through_record = through_proxy.send(:load_target)

          if through_record && !record
            through_record.destroy
          elsif record
            attributes = construct_join_attributes(record)

            if through_record
              through_record.update_attributes(attributes)
            elsif owner.new_record?
              through_proxy.build(attributes)
            else
              through_proxy.create(attributes)
            end
          end
        end
    end
  end
end
module ActiveRecord
  module Associations
    class JoinDependency # :nodoc:
      class JoinAssociation < JoinPart # :nodoc:
        include JoinHelper

        # The reflection of the association represented
        attr_reader :reflection

        # The JoinDependency object which this JoinAssociation exists within. This is mainly
        # relevant for generating aliases which do not conflict with other joins which are
        # part of the query.
        attr_reader :join_dependency

        # A JoinBase instance representing the active record we are joining onto.
        # (So in Author.has_many :posts, the Author would be that base record.)
        attr_reader :parent

        # What type of join will be generated, either Arel::InnerJoin (default) or Arel::OuterJoin
        attr_accessor :join_type

        # These implement abstract methods from the superclass
        attr_reader :aliased_prefix

        attr_reader :tables

        delegate :options, :through_reflection, :source_reflection, :chain, :to => :reflection
        delegate :table, :table_name, :to => :parent, :prefix => :parent
        delegate :alias_tracker, :to => :join_dependency

        alias :alias_suffix :parent_table_name

        def initialize(reflection, join_dependency, parent = nil)
          reflection.check_validity!

          if reflection.options[:polymorphic]
            raise EagerLoadPolymorphicError.new(reflection)
          end

          super(reflection.klass)

          @reflection      = reflection
          @join_dependency = join_dependency
          @parent          = parent
          @join_type       = Arel::InnerJoin
          @aliased_prefix  = "t#{ join_dependency.join_parts.size }"
          @tables          = construct_tables.reverse
        end

        def ==(other)
          other.class == self.class &&
            other.reflection == reflection &&
            other.parent == parent
        end

        def find_parent_in(other_join_dependency)
          other_join_dependency.join_parts.detect do |join_part|
            parent == join_part
          end
        end

        def join_to(relation)
          tables        = @tables.dup
          foreign_table = parent_table
          foreign_klass = parent.active_record

          # The chain starts with the target table, but we want to end with it here (makes
          # more sense in this context), so we reverse
          chain.reverse.each_with_index do |reflection, i|
            table = tables.shift

            case reflection.source_macro
            when :belongs_to
              key         = reflection.association_primary_key
              foreign_key = reflection.foreign_key
            when :has_and_belongs_to_many
              # Join the join table first...
              relation.from(join(
                table,
                table[reflection.foreign_key].
                  eq(foreign_table[reflection.active_record_primary_key])
              ))

              foreign_table, table = table, tables.shift

              key         = reflection.association_primary_key
              foreign_key = reflection.association_foreign_key
            else
              key         = reflection.foreign_key
              foreign_key = reflection.active_record_primary_key
            end

            constraint = build_constraint(reflection, table, key, foreign_table, foreign_key)

            conditions = self.conditions[i].dup
            conditions << { reflection.type => foreign_klass.base_class.name } if reflection.type

            unless conditions.empty?
              constraint = constraint.and(sanitize(conditions, table))
            end

            relation.from(join(table, constraint))

            # The current table in this iteration becomes the foreign table in the next
            foreign_table, foreign_klass = table, reflection.klass
          end

          relation
        end

        def build_constraint(reflection, table, key, foreign_table, foreign_key)
          constraint = table[key].eq(foreign_table[foreign_key])

          if reflection.klass.finder_needs_type_condition?
            constraint = table.create_and([
              constraint,
              reflection.klass.send(:type_condition, table)
            ])
          end

          constraint
        end

        def join_relation(joining_relation)
          self.join_type = Arel::OuterJoin
          joining_relation.joins(self)
        end

        def table
          tables.last
        end

        def aliased_table_name
          table.table_alias || table.name
        end

        def conditions
          @conditions ||= reflection.conditions.reverse
        end

        private

        def interpolate(conditions)
          if conditions.respond_to?(:to_proc)
            instance_eval(&conditions)
          else
            conditions
          end
        end

      end
    end
  end
end
module ActiveRecord
  module Associations
    class JoinDependency # :nodoc:
      class JoinBase < JoinPart # :nodoc:
        def ==(other)
          other.class == self.class &&
            other.active_record == active_record
        end

        def aliased_prefix
          "t0"
        end

        def table
          Arel::Table.new(table_name, arel_engine)
        end

        def aliased_table_name
          active_record.table_name
        end
      end
    end
  end
end
module ActiveRecord
  module Associations
    class JoinDependency # :nodoc:
      # A JoinPart represents a part of a JoinDependency. It is an abstract class, inherited
      # by JoinBase and JoinAssociation. A JoinBase represents the Active Record which
      # everything else is being joined onto. A JoinAssociation represents an association which
      # is joining to the base. A JoinAssociation may result in more than one actual join
      # operations (for example a has_and_belongs_to_many JoinAssociation would result in
      # two; one for the join table and one for the target table).
      class JoinPart # :nodoc:
        # The Active Record class which this join part is associated 'about'; for a JoinBase
        # this is the actual base model, for a JoinAssociation this is the target model of the
        # association.
        attr_reader :active_record

        delegate :table_name, :column_names, :primary_key, :reflections, :arel_engine, :to => :active_record

        def initialize(active_record)
          @active_record = active_record
          @cached_record = {}
          @column_names_with_alias = nil
        end

        def aliased_table
          Arel::Nodes::TableAlias.new table, aliased_table_name
        end

        def ==(other)
          raise NotImplementedError
        end

        # An Arel::Table for the active_record
        def table
          raise NotImplementedError
        end

        # The prefix to be used when aliasing columns in the active_record's table
        def aliased_prefix
          raise NotImplementedError
        end

        # The alias for the active_record's table
        def aliased_table_name
          raise NotImplementedError
        end

        # The alias for the primary key of the active_record's table
        def aliased_primary_key
          "#{aliased_prefix}_r0"
        end

        # An array of [column_name, alias] pairs for the table
        def column_names_with_alias
          unless @column_names_with_alias
            @column_names_with_alias = []

            ([primary_key] + (column_names - [primary_key])).each_with_index do |column_name, i|
              @column_names_with_alias << [column_name, "#{aliased_prefix}_r#{i}"]
            end
          end
          @column_names_with_alias
        end

        def extract_record(row)
          Hash[column_names_with_alias.map{|cn, an| [cn, row[an]]}]
        end

        def record_id(row)
          row[aliased_primary_key]
        end

        def instantiate(row)
          @cached_record[record_id(row)] ||= active_record.send(:instantiate, extract_record(row))
        end
      end
    end
  end
end
module ActiveRecord
  module Associations
    class JoinDependency # :nodoc:
      autoload :JoinPart,        'active_record/associations/join_dependency/join_part'
      autoload :JoinBase,        'active_record/associations/join_dependency/join_base'
      autoload :JoinAssociation, 'active_record/associations/join_dependency/join_association'

      attr_reader :join_parts, :reflections, :alias_tracker, :active_record

      def initialize(base, associations, joins)
        @active_record = base
        @table_joins   = joins
        @join_parts    = [JoinBase.new(base)]
        @associations  = {}
        @reflections   = []
        @alias_tracker = AliasTracker.new(base.connection, joins)
        @alias_tracker.aliased_name_for(base.table_name) # Updates the count for base.table_name to 1
        build(associations)
      end

      def graft(*associations)
        associations.each do |association|
          join_associations.detect {|a| association == a} ||
            build(association.reflection.name, association.find_parent_in(self) || join_base, association.join_type)
        end
        self
      end

      def join_associations
        join_parts.last(join_parts.length - 1)
      end

      def join_base
        join_parts.first
      end

      def columns
        join_parts.collect { |join_part|
          table = join_part.aliased_table
          join_part.column_names_with_alias.collect{ |column_name, aliased_name|
            table[column_name].as Arel.sql(aliased_name)
          }
        }.flatten
      end

      def instantiate(rows)
        primary_key = join_base.aliased_primary_key
        parents = {}

        records = rows.map { |model|
          primary_id = model[primary_key]
          parent = parents[primary_id] ||= join_base.instantiate(model)
          construct(parent, @associations, join_associations, model)
          parent
        }.uniq

        remove_duplicate_results!(active_record, records, @associations)
        records
      end

      def remove_duplicate_results!(base, records, associations)
        case associations
        when Symbol, String
          reflection = base.reflections[associations]
          remove_uniq_by_reflection(reflection, records)
        when Array
          associations.each do |association|
            remove_duplicate_results!(base, records, association)
          end
        when Hash
          associations.keys.each do |name|
            reflection = base.reflections[name]
            remove_uniq_by_reflection(reflection, records)

            parent_records = []
            records.each do |record|
              if descendant = record.send(reflection.name)
                if reflection.collection?
                  parent_records.concat descendant.target.uniq
                else
                  parent_records << descendant
                end
              end
            end

            remove_duplicate_results!(reflection.klass, parent_records, associations[name]) unless parent_records.empty?
          end
        end
      end

      protected

      def cache_joined_association(association)
        associations = []
        parent = association.parent
        while parent != join_base
          associations.unshift(parent.reflection.name)
          parent = parent.parent
        end
        ref = @associations
        associations.each do |key|
          ref = ref[key]
        end
        ref[association.reflection.name] ||= {}
      end

      def build(associations, parent = nil, join_type = Arel::InnerJoin)
        parent ||= join_parts.last
        case associations
        when Symbol, String
          reflection = parent.reflections[associations.to_s.intern] or
          raise ConfigurationError, "Association named '#{ associations }' was not found; perhaps you misspelled it?"
          unless join_association = find_join_association(reflection, parent)
            @reflections << reflection
            join_association = build_join_association(reflection, parent)
            join_association.join_type = join_type
            @join_parts << join_association
            cache_joined_association(join_association)
          end
          join_association
        when Array
          associations.each do |association|
            build(association, parent, join_type)
          end
        when Hash
          associations.keys.sort_by { |a| a.to_s }.each do |name|
            join_association = build(name, parent, join_type)
            build(associations[name], join_association, join_type)
          end
        else
          raise ConfigurationError, associations.inspect
        end
      end

      def find_join_association(name_or_reflection, parent)
        if String === name_or_reflection
          name_or_reflection = name_or_reflection.to_sym
        end

        join_associations.detect { |j|
          j.reflection == name_or_reflection && j.parent == parent
        }
      end

      def remove_uniq_by_reflection(reflection, records)
        if reflection && reflection.collection?
          records.each { |record| record.send(reflection.name).target.uniq! }
        end
      end

      def build_join_association(reflection, parent)
        JoinAssociation.new(reflection, self, parent)
      end

      def construct(parent, associations, join_parts, row)
        case associations
        when Symbol, String
          name = associations.to_s

          join_part = join_parts.detect { |j|
            j.reflection.name.to_s == name &&
              j.parent_table_name == parent.class.table_name }

            raise(ConfigurationError, "No such association") unless join_part

            join_parts.delete(join_part)
            construct_association(parent, join_part, row)
        when Array
          associations.each do |association|
            construct(parent, association, join_parts, row)
          end
        when Hash
          associations.sort_by { |k,_| k.to_s }.each do |association_name, assoc|
            association = construct(parent, association_name, join_parts, row)
            construct(association, assoc, join_parts, row) if association
          end
        else
          raise ConfigurationError, associations.inspect
        end
      end

      def construct_association(record, join_part, row)
        return if record.id.to_s != join_part.parent.record_id(row).to_s

        macro = join_part.reflection.macro
        if macro == :has_one
          return record.association(join_part.reflection.name).target if record.association_cache.key?(join_part.reflection.name)
          association = join_part.instantiate(row) unless row[join_part.aliased_primary_key].nil?
          set_target_and_inverse(join_part, association, record)
        else
          association = join_part.instantiate(row) unless row[join_part.aliased_primary_key].nil?
          case macro
          when :has_many, :has_and_belongs_to_many
            other = record.association(join_part.reflection.name)
            other.loaded!
            other.target.push(association) if association
            other.set_inverse_instance(association)
          when :belongs_to
            set_target_and_inverse(join_part, association, record)
          else
            raise ConfigurationError, "unknown macro: #{join_part.reflection.macro}"
          end
        end
        association
      end

      def set_target_and_inverse(join_part, association, record)
        other = record.association(join_part.reflection.name)
        other.target = association
        other.set_inverse_instance(association)
      end
    end
  end
end
module ActiveRecord
  module Associations
    # Helper class module which gets mixed into JoinDependency::JoinAssociation and AssociationScope
    module JoinHelper #:nodoc:

      def join_type
        Arel::InnerJoin
      end

      private

      def construct_tables
        tables = []
        chain.each do |reflection|
          tables << alias_tracker.aliased_table_for(
            table_name_for(reflection),
            table_alias_for(reflection, reflection != self.reflection)
          )

          if reflection.source_macro == :has_and_belongs_to_many
            tables << alias_tracker.aliased_table_for(
              (reflection.source_reflection || reflection).options[:join_table],
              table_alias_for(reflection, true)
            )
          end
        end
        tables
      end

      def table_name_for(reflection)
        reflection.table_name
      end

      def table_alias_for(reflection, join = false)
        name = "#{reflection.plural_name}_#{alias_suffix}"
        name << "_join" if join
        name
      end

      def join(table, constraint)
        table.create_join(table, table.create_on(constraint), join_type)
      end

      def sanitize(conditions, table)
        conditions = conditions.map do |condition|
          condition = active_record.send(:sanitize_sql, interpolate(condition), table.table_alias || table.name)
          condition = Arel.sql(condition) unless condition.is_a?(Arel::Node)
          condition
        end

        conditions.length == 1 ? conditions.first : Arel::Nodes::And.new(conditions)
      end
    end
  end
end
module ActiveRecord
  module Associations
    class Preloader
      class Association #:nodoc:
        attr_reader :owners, :reflection, :preload_options, :model, :klass

        def initialize(klass, owners, reflection, preload_options)
          @klass           = klass
          @owners          = owners
          @reflection      = reflection
          @preload_options = preload_options || {}
          @model           = owners.first && owners.first.class
          @scoped          = nil
          @owners_by_key   = nil
        end

        def run
          unless owners.first.association(reflection.name).loaded?
            preload
          end
        end

        def preload
          raise NotImplementedError
        end

        def scoped
          @scoped ||= build_scope
        end

        def records_for(ids)
          scoped.where(association_key.in(ids))
        end

        def table
          klass.arel_table
        end

        # The name of the key on the associated records
        def association_key_name
          raise NotImplementedError
        end

        # This is overridden by HABTM as the condition should be on the foreign_key column in
        # the join table
        def association_key
          table[association_key_name]
        end

        # The name of the key on the model which declares the association
        def owner_key_name
          raise NotImplementedError
        end

        # We're converting to a string here because postgres will return the aliased association
        # key in a habtm as a string (for whatever reason)
        def owners_by_key
          @owners_by_key ||= owners.group_by do |owner|
            key = owner[owner_key_name]
            key && key.to_s
          end
        end

        def options
          reflection.options
        end

        private

        def associated_records_by_owner
          owners_map = owners_by_key
          owner_keys = owners_map.keys.compact

          if klass.nil? || owner_keys.empty?
            records = []
          else
            # Some databases impose a limit on the number of ids in a list (in Oracle it's 1000)
            # Make several smaller queries if necessary or make one query if the adapter supports it
            sliced  = owner_keys.each_slice(model.connection.in_clause_length || owner_keys.size)
            records = sliced.map { |slice| records_for(slice) }.flatten
          end

          # Each record may have multiple owners, and vice-versa
          records_by_owner = Hash[owners.map { |owner| [owner, []] }]
          records.each do |record|
            owner_key = record[association_key_name].to_s

            owners_map[owner_key].each do |owner|
              records_by_owner[owner] << record
            end
          end
          records_by_owner
        end

        def build_scope
          scope = klass.scoped

          scope = scope.where(process_conditions(options[:conditions]))
          scope = scope.where(process_conditions(preload_options[:conditions]))

          scope = scope.select(preload_options[:select] || options[:select] || table[Arel.star])
          scope = scope.includes(preload_options[:include] || options[:include])

          if options[:as]
            scope = scope.where(
              klass.table_name => {
                reflection.type => model.base_class.sti_name
              }
            )
          end

          scope
        end

        def process_conditions(conditions)
          if conditions.respond_to?(:to_proc)
            conditions = klass.send(:instance_eval, &conditions)
          end

          conditions
        end
      end
    end
  end
end
module ActiveRecord
  module Associations
    class Preloader
      class BelongsTo < SingularAssociation #:nodoc:

        def association_key_name
          reflection.options[:primary_key] || klass && klass.primary_key
        end

        def owner_key_name
          reflection.foreign_key
        end

      end
    end
  end
end
module ActiveRecord
  module Associations
    class Preloader
      class CollectionAssociation < Association #:nodoc:

        private

        def build_scope
          super.order(preload_options[:order] || options[:order])
        end

        def preload
          associated_records_by_owner.each do |owner, records|
            association = owner.association(reflection.name)
            association.loaded!
            association.target.concat(records)
            records.each { |record| association.set_inverse_instance(record) }
          end
        end

      end
    end
  end
end
module ActiveRecord
  module Associations
    class Preloader
      class HasAndBelongsToMany < CollectionAssociation #:nodoc:
        attr_reader :join_table

        def initialize(klass, records, reflection, preload_options)
          super
          @join_table = Arel::Table.new(options[:join_table]).alias('t0')
        end

        # Unlike the other associations, we want to get a raw array of rows so that we can
        # access the aliased column on the join table
        def records_for(ids)
          scope = super
          klass.connection.select_all(scope.arel, 'SQL', scope.bind_values)
        end

        def owner_key_name
          reflection.active_record_primary_key
        end

        def association_key_name
          'ar_association_key_name'
        end

        def association_key
          join_table[reflection.foreign_key]
        end

        private

        # Once we have used the join table column (in super), we manually instantiate the
        # actual records, ensuring that we don't create more than one instances of the same
        # record
        def associated_records_by_owner
          records = {}
          super.each do |owner_key, rows|
            rows.map! { |row| records[row[klass.primary_key]] ||= klass.instantiate(row) }
          end
        end

        def build_scope
          super.joins(join).select(join_select)
        end

        def join_select
          association_key.as(Arel.sql(association_key_name))
        end

        def join
          condition = table[reflection.association_primary_key].eq(
            join_table[reflection.association_foreign_key])

          table.create_join(join_table, table.create_on(condition))
        end
      end
    end
  end
end
module ActiveRecord
  module Associations
    class Preloader
      class HasMany < CollectionAssociation #:nodoc:

        def association_key_name
          reflection.foreign_key
        end

        def owner_key_name
          reflection.active_record_primary_key
        end

      end
    end
  end
end
module ActiveRecord
  module Associations
    class Preloader
      class HasManyThrough < CollectionAssociation #:nodoc:
        include ThroughAssociation

        def associated_records_by_owner
          super.each do |owner, records|
            records.uniq! if options[:uniq]
          end
        end
      end
    end
  end
end
module ActiveRecord
  module Associations
    class Preloader
      class HasOne < SingularAssociation #:nodoc:

        def association_key_name
          reflection.foreign_key
        end

        def owner_key_name
          reflection.active_record_primary_key
        end

        private

        def build_scope
          super.order(preload_options[:order] || options[:order])
        end

      end
    end
  end
end
module ActiveRecord
  module Associations
    class Preloader
      class HasOneThrough < SingularAssociation #:nodoc:
        include ThroughAssociation
      end
    end
  end
end
module ActiveRecord
  module Associations
    class Preloader
      class SingularAssociation < Association #:nodoc:

        private

        def preload
          associated_records_by_owner.each do |owner, associated_records|
            record = associated_records.first

            association = owner.association(reflection.name)
            association.target = record
            association.set_inverse_instance(record)
          end
        end

      end
    end
  end
end
module ActiveRecord
  module Associations
    class Preloader
      module ThroughAssociation #:nodoc:

        def through_reflection
          reflection.through_reflection
        end

        def source_reflection
          reflection.source_reflection
        end

        def associated_records_by_owner
          through_records = through_records_by_owner

          ActiveRecord::Associations::Preloader.new(
            through_records.values.flatten,
            source_reflection.name, options
          ).run

          through_records.each do |owner, records|
            records.map! { |r| r.send(source_reflection.name) }.flatten!
            records.compact!
          end
        end

        private

        def through_records_by_owner
          ActiveRecord::Associations::Preloader.new(
            owners, through_reflection.name,
            through_options
          ).run

          Hash[owners.map do |owner|
            through_records = Array.wrap(owner.send(through_reflection.name))

            # Dont cache the association - we would only be caching a subset
            if reflection.options[:source_type] && through_reflection.collection?
              owner.association(through_reflection.name).reset
            end

            [owner, through_records]
          end]
        end

        def through_options
          through_options = {}

          if options[:source_type]
            through_options[:conditions] = { reflection.foreign_type => options[:source_type] }
          else
            if options[:conditions]
              through_options[:include]    = options[:include] || options[:source]
              through_options[:conditions] = options[:conditions]
            end

            through_options[:order] = options[:order]
          end

          through_options
        end
      end
    end
  end
end
module ActiveRecord
  module Associations
    # Implements the details of eager loading of Active Record associations.
    #
    # Note that 'eager loading' and 'preloading' are actually the same thing.
    # However, there are two different eager loading strategies.
    #
    # The first one is by using table joins. This was only strategy available
    # prior to Rails 2.1. Suppose that you have an Author model with columns
    # 'name' and 'age', and a Book model with columns 'name' and 'sales'. Using
    # this strategy, Active Record would try to retrieve all data for an author
    # and all of its books via a single query:
    #
    #   SELECT * FROM authors
    #   LEFT OUTER JOIN books ON authors.id = books.id
    #   WHERE authors.name = 'Ken Akamatsu'
    #
    # However, this could result in many rows that contain redundant data. After
    # having received the first row, we already have enough data to instantiate
    # the Author object. In all subsequent rows, only the data for the joined
    # 'books' table is useful; the joined 'authors' data is just redundant, and
    # processing this redundant data takes memory and CPU time. The problem
    # quickly becomes worse and worse as the level of eager loading increases
    # (i.e. if Active Record is to eager load the associations' associations as
    # well).
    #
    # The second strategy is to use multiple database queries, one for each
    # level of association. Since Rails 2.1, this is the default strategy. In
    # situations where a table join is necessary (e.g. when the +:conditions+
    # option references an association's column), it will fallback to the table
    # join strategy.
    class Preloader #:nodoc:
      extend ActiveSupport::Autoload

      eager_autoload do
        autoload :Association,           'active_record/associations/preloader/association'
        autoload :SingularAssociation,   'active_record/associations/preloader/singular_association'
        autoload :CollectionAssociation, 'active_record/associations/preloader/collection_association'
        autoload :ThroughAssociation,    'active_record/associations/preloader/through_association'

        autoload :HasMany,             'active_record/associations/preloader/has_many'
        autoload :HasManyThrough,      'active_record/associations/preloader/has_many_through'
        autoload :HasOne,              'active_record/associations/preloader/has_one'
        autoload :HasOneThrough,       'active_record/associations/preloader/has_one_through'
        autoload :HasAndBelongsToMany, 'active_record/associations/preloader/has_and_belongs_to_many'
        autoload :BelongsTo,           'active_record/associations/preloader/belongs_to'
      end

      attr_reader :records, :associations, :options, :model

      # Eager loads the named associations for the given Active Record record(s).
      #
      # In this description, 'association name' shall refer to the name passed
      # to an association creation method. For example, a model that specifies
      # <tt>belongs_to :author</tt>, <tt>has_many :buyers</tt> has association
      # names +:author+ and +:buyers+.
      #
      # == Parameters
      # +records+ is an array of ActiveRecord::Base. This array needs not be flat,
      # i.e. +records+ itself may also contain arrays of records. In any case,
      # +preload_associations+ will preload the all associations records by
      # flattening +records+.
      #
      # +associations+ specifies one or more associations that you want to
      # preload. It may be:
      # - a Symbol or a String which specifies a single association name. For
      #   example, specifying +:books+ allows this method to preload all books
      #   for an Author.
      # - an Array which specifies multiple association names. This array
      #   is processed recursively. For example, specifying <tt>[:avatar, :books]</tt>
      #   allows this method to preload an author's avatar as well as all of his
      #   books.
      # - a Hash which specifies multiple association names, as well as
      #   association names for the to-be-preloaded association objects. For
      #   example, specifying <tt>{ :author => :avatar }</tt> will preload a
      #   book's author, as well as that author's avatar.
      #
      # +:associations+ has the same format as the +:include+ option for
      # <tt>ActiveRecord::Base.find</tt>. So +associations+ could look like this:
      #
      #   :books
      #   [ :books, :author ]
      #   { :author => :avatar }
      #   [ :books, { :author => :avatar } ]
      #
      # +options+ contains options that will be passed to ActiveRecord::Base#find
      # (which is called under the hood for preloading records). But it is passed
      # only one level deep in the +associations+ argument, i.e. it's not passed
      # to the child associations when +associations+ is a Hash.
      def initialize(records, associations, options = {})
        @records      = Array.wrap(records).compact.uniq
        @associations = Array.wrap(associations)
        @options      = options
      end

      def run
        unless records.empty?
          associations.each { |association| preload(association) }
        end
      end

      private

      def preload(association)
        case association
        when Hash
          preload_hash(association)
        when String, Symbol
          preload_one(association.to_sym)
        else
          raise ArgumentError, "#{association.inspect} was not recognised for preload"
        end
      end

      def preload_hash(association)
        association.each do |parent, child|
          Preloader.new(records, parent, options).run
          Preloader.new(records.map { |record| record.send(parent) }.flatten, child).run
        end
      end

      # Not all records have the same class, so group then preload group on the reflection
      # itself so that if various subclass share the same association then we do not split
      # them unnecessarily
      #
      # Additionally, polymorphic belongs_to associations can have multiple associated
      # classes, depending on the polymorphic_type field. So we group by the classes as
      # well.
      def preload_one(association)
        grouped_records(association).each do |reflection, klasses|
          klasses.each do |klass, records|
            preloader_for(reflection).new(klass, records, reflection, options).run
          end
        end
      end

      def grouped_records(association)
        Hash[
          records_by_reflection(association).map do |reflection, records|
            [reflection, records.group_by { |record| association_klass(reflection, record) }]
          end
        ]
      end

      def records_by_reflection(association)
        records.group_by do |record|
          reflection = record.class.reflections[association]

          unless reflection
            raise ActiveRecord::ConfigurationError, "Association named '#{association}' was not found; " \
                                                    "perhaps you misspelled it?"
          end

          reflection
        end
      end

      def association_klass(reflection, record)
        if reflection.macro == :belongs_to && reflection.options[:polymorphic]
          klass = record.send(reflection.foreign_type)
          klass && klass.constantize
        else
          reflection.klass
        end
      end

      def preloader_for(reflection)
        case reflection.macro
        when :has_many
          reflection.options[:through] ? HasManyThrough : HasMany
        when :has_one
          reflection.options[:through] ? HasOneThrough : HasOne
        when :has_and_belongs_to_many
          HasAndBelongsToMany
        when :belongs_to
          BelongsTo
        end
      end
    end
  end
end
module ActiveRecord
  module Associations
    class SingularAssociation < Association #:nodoc:
      # Implements the reader method, e.g. foo.bar for Foo.has_one :bar
      def reader(force_reload = false)
        if force_reload
          klass.uncached { reload }
        elsif !loaded? || stale_target?
          reload
        end

        target
      end

      # Implements the writer method, e.g. foo.items= for Foo.has_many :items
      def writer(record)
        replace(record)
      end

      def create(attributes = {}, options = {}, &block)
        create_record(attributes, options, &block)
      end

      def create!(attributes = {}, options = {}, &block)
        create_record(attributes, options, true, &block)
      end

      def build(attributes = {}, options = {})
        record = build_record(attributes, options)
        yield(record) if block_given?
        set_new_record(record)
        record
      end

      private

        def create_scope
          scoped.scope_for_create.stringify_keys.except(klass.primary_key)
        end

        def find_target
          scoped.first.tap { |record| set_inverse_instance(record) }
        end

        # Implemented by subclasses
        def replace(record)
          raise NotImplementedError, "Subclasses must implement a replace(record) method"
        end

        def set_new_record(record)
          replace(record)
        end

        def create_record(attributes, options, raise_error = false)
          record = build_record(attributes, options)
          yield(record) if block_given?
          saved = record.save
          set_new_record(record)
          raise RecordInvalid.new(record) if !saved && raise_error
          record
        end
    end
  end
end
module ActiveRecord
  # = Active Record Through Association
  module Associations
    module ThroughAssociation #:nodoc:

      delegate :source_reflection, :through_reflection, :chain, :to => :reflection

      protected

        # We merge in these scopes for two reasons:
        #
        #   1. To get the default_scope conditions for any of the other reflections in the chain
        #   2. To get the type conditions for any STI models in the chain
        def target_scope
          scope = super
          chain[1..-1].each do |reflection|
            scope = scope.merge(
              reflection.klass.scoped.with_default_scope.
                except(:select, :create_with, :includes, :preload, :joins, :eager_load)
            )
          end
          scope
        end

      private

        # Construct attributes for :through pointing to owner and associate. This is used by the
        # methods which create and delete records on the association.
        #
        # We only support indirectly modifying through associations which has a belongs_to source.
        # This is the "has_many :tags, :through => :taggings" situation, where the join model
        # typically has a belongs_to on both side. In other words, associations which could also
        # be represented as has_and_belongs_to_many associations.
        #
        # We do not support creating/deleting records on the association where the source has
        # some other type, because this opens up a whole can of worms, and in basically any
        # situation it is more natural for the user to just create or modify their join records
        # directly as required.
        def construct_join_attributes(*records)
          ensure_mutable

          join_attributes = {
            source_reflection.foreign_key =>
              records.map { |record|
                record.send(source_reflection.association_primary_key(reflection.klass))
              }
          }

          if options[:source_type]
            join_attributes[source_reflection.foreign_type] =
              records.map { |record| record.class.base_class.name }
          end

          if records.count == 1
            Hash[join_attributes.map { |k, v| [k, v.first] }]
          else
            join_attributes
          end
        end

        # Note: this does not capture all cases, for example it would be crazy to try to
        # properly support stale-checking for nested associations.
        def stale_state
          if through_reflection.macro == :belongs_to
            owner[through_reflection.foreign_key].to_s
          end
        end

        def foreign_key_present?
          through_reflection.macro == :belongs_to &&
          !owner[through_reflection.foreign_key].nil?
        end

        def ensure_mutable
          if source_reflection.macro != :belongs_to
            raise HasManyThroughCantAssociateThroughHasOneOrManyReflection.new(owner, reflection)
          end
        end

        def ensure_not_nested
          if reflection.nested?
            raise HasManyThroughNestedAssociationsAreReadonly.new(owner, reflection)
          end
        end
    end
  end
end
require 'active_support/core_ext/array/wrap'
require 'active_support/core_ext/enumerable'
require 'active_support/core_ext/module/delegation'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/conversions'
require 'active_support/core_ext/module/remove_method'
require 'active_support/core_ext/class/attribute'

module ActiveRecord
  class InverseOfAssociationNotFoundError < ActiveRecordError #:nodoc:
    def initialize(reflection, associated_class = nil)
      super("Could not find the inverse association for #{reflection.name} (#{reflection.options[:inverse_of].inspect} in #{associated_class.nil? ? reflection.class_name : associated_class.name})")
    end
  end

  class HasManyThroughAssociationNotFoundError < ActiveRecordError #:nodoc:
    def initialize(owner_class_name, reflection)
      super("Could not find the association #{reflection.options[:through].inspect} in model #{owner_class_name}")
    end
  end

  class HasManyThroughAssociationPolymorphicSourceError < ActiveRecordError #:nodoc:
    def initialize(owner_class_name, reflection, source_reflection)
      super("Cannot have a has_many :through association '#{owner_class_name}##{reflection.name}' on the polymorphic object '#{source_reflection.class_name}##{source_reflection.name}'.")
    end
  end

  class HasManyThroughAssociationPolymorphicThroughError < ActiveRecordError #:nodoc:
    def initialize(owner_class_name, reflection)
      super("Cannot have a has_many :through association '#{owner_class_name}##{reflection.name}' which goes through the polymorphic association '#{owner_class_name}##{reflection.through_reflection.name}'.")
    end
  end

  class HasManyThroughAssociationPointlessSourceTypeError < ActiveRecordError #:nodoc:
    def initialize(owner_class_name, reflection, source_reflection)
      super("Cannot have a has_many :through association '#{owner_class_name}##{reflection.name}' with a :source_type option if the '#{reflection.through_reflection.class_name}##{source_reflection.name}' is not polymorphic. Try removing :source_type on your association.")
    end
  end

  class HasOneThroughCantAssociateThroughCollection < ActiveRecordError #:nodoc:
    def initialize(owner_class_name, reflection, through_reflection)
      super("Cannot have a has_one :through association '#{owner_class_name}##{reflection.name}' where the :through association '#{owner_class_name}##{through_reflection.name}' is a collection. Specify a has_one or belongs_to association in the :through option instead.")
    end
  end

  class HasManyThroughSourceAssociationNotFoundError < ActiveRecordError #:nodoc:
    def initialize(reflection)
      through_reflection      = reflection.through_reflection
      source_reflection_names = reflection.source_reflection_names
      source_associations     = reflection.through_reflection.klass.reflect_on_all_associations.collect { |a| a.name.inspect }
      super("Could not find the source association(s) #{source_reflection_names.collect{ |a| a.inspect }.to_sentence(:two_words_connector => ' or ', :last_word_connector => ', or ', :locale => :en)} in model #{through_reflection.klass}. Try 'has_many #{reflection.name.inspect}, :through => #{through_reflection.name.inspect}, :source => <name>'. Is it one of #{source_associations.to_sentence(:two_words_connector => ' or ', :last_word_connector => ', or ', :locale => :en)}?")
    end
  end

  class HasManyThroughCantAssociateThroughHasOneOrManyReflection < ActiveRecordError #:nodoc:
    def initialize(owner, reflection)
      super("Cannot modify association '#{owner.class.name}##{reflection.name}' because the source reflection class '#{reflection.source_reflection.class_name}' is associated to '#{reflection.through_reflection.class_name}' via :#{reflection.source_reflection.macro}.")
    end
  end

  class HasManyThroughCantAssociateNewRecords < ActiveRecordError #:nodoc:
    def initialize(owner, reflection)
      super("Cannot associate new records through '#{owner.class.name}##{reflection.name}' on '#{reflection.source_reflection.class_name rescue nil}##{reflection.source_reflection.name rescue nil}'. Both records must have an id in order to create the has_many :through record associating them.")
    end
  end

  class HasManyThroughCantDissociateNewRecords < ActiveRecordError #:nodoc:
    def initialize(owner, reflection)
      super("Cannot dissociate new records through '#{owner.class.name}##{reflection.name}' on '#{reflection.source_reflection.class_name rescue nil}##{reflection.source_reflection.name rescue nil}'. Both records must have an id in order to delete the has_many :through record associating them.")
    end
  end

  class HasManyThroughNestedAssociationsAreReadonly < ActiveRecordError #:nodoc:
    def initialize(owner, reflection)
      super("Cannot modify association '#{owner.class.name}##{reflection.name}' because it goes through more than one other association.")
    end
  end

  class HasAndBelongsToManyAssociationForeignKeyNeeded < ActiveRecordError #:nodoc:
    def initialize(reflection)
      super("Cannot create self referential has_and_belongs_to_many association on '#{reflection.class_name rescue nil}##{reflection.name rescue nil}'. :association_foreign_key cannot be the same as the :foreign_key.")
    end
  end

  class EagerLoadPolymorphicError < ActiveRecordError #:nodoc:
    def initialize(reflection)
      super("Can not eagerly load the polymorphic association #{reflection.name.inspect}")
    end
  end

  class ReadOnlyAssociation < ActiveRecordError #:nodoc:
    def initialize(reflection)
      super("Can not add to a has_many :through association. Try adding to #{reflection.through_reflection.name.inspect}.")
    end
  end

  # This error is raised when trying to destroy a parent instance in N:1 or 1:1 associations
  # (has_many, has_one) when there is at least 1 child associated instance.
  # ex: if @project.tasks.size > 0, DeleteRestrictionError will be raised when trying to destroy @project
  class DeleteRestrictionError < ActiveRecordError #:nodoc:
    def initialize(name)
      super("Cannot delete record because of dependent #{name}")
    end
  end

  # See ActiveRecord::Associations::ClassMethods for documentation.
  module Associations # :nodoc:
    extend ActiveSupport::Autoload
    extend ActiveSupport::Concern

    # These classes will be loaded when associations are created.
    # So there is no need to eager load them.
    autoload :Association,           'active_record/associations/association'
    autoload :SingularAssociation,   'active_record/associations/singular_association'
    autoload :CollectionAssociation, 'active_record/associations/collection_association'
    autoload :CollectionProxy,       'active_record/associations/collection_proxy'

    autoload :BelongsToAssociation,            'active_record/associations/belongs_to_association'
    autoload :BelongsToPolymorphicAssociation, 'active_record/associations/belongs_to_polymorphic_association'
    autoload :HasAndBelongsToManyAssociation,  'active_record/associations/has_and_belongs_to_many_association'
    autoload :HasManyAssociation,              'active_record/associations/has_many_association'
    autoload :HasManyThroughAssociation,       'active_record/associations/has_many_through_association'
    autoload :HasOneAssociation,               'active_record/associations/has_one_association'
    autoload :HasOneThroughAssociation,        'active_record/associations/has_one_through_association'
    autoload :ThroughAssociation,              'active_record/associations/through_association'

    module Builder #:nodoc:
      autoload :Association,           'active_record/associations/builder/association'
      autoload :SingularAssociation,   'active_record/associations/builder/singular_association'
      autoload :CollectionAssociation, 'active_record/associations/builder/collection_association'

      autoload :BelongsTo,           'active_record/associations/builder/belongs_to'
      autoload :HasOne,              'active_record/associations/builder/has_one'
      autoload :HasMany,             'active_record/associations/builder/has_many'
      autoload :HasAndBelongsToMany, 'active_record/associations/builder/has_and_belongs_to_many'
    end

    eager_autoload do
      autoload :Preloader,        'active_record/associations/preloader'
      autoload :JoinDependency,   'active_record/associations/join_dependency'
      autoload :AssociationScope, 'active_record/associations/association_scope'
      autoload :AliasTracker,     'active_record/associations/alias_tracker'
      autoload :JoinHelper,       'active_record/associations/join_helper'
    end

    # Clears out the association cache.
    def clear_association_cache #:nodoc:
      @association_cache.clear if persisted?
    end

    # :nodoc:
    attr_reader :association_cache

    # Returns the association instance for the given name, instantiating it if it doesn't already exist
    def association(name) #:nodoc:
      association = association_instance_get(name)

      if association.nil?
        reflection  = self.class.reflect_on_association(name)
        association = reflection.association_class.new(self, reflection)
        association_instance_set(name, association)
      end

      association
    end

    private
      # Returns the specified association instance if it responds to :loaded?, nil otherwise.
      def association_instance_get(name)
        @association_cache[name.to_sym]
      end

      # Set the specified association instance.
      def association_instance_set(name, association)
        @association_cache[name] = association
      end

    # Associations are a set of macro-like class methods for tying objects together through
    # foreign keys. They express relationships like "Project has one Project Manager"
    # or "Project belongs to a Portfolio". Each macro adds a number of methods to the
    # class which are specialized according to the collection or association symbol and the
    # options hash. It works much the same way as Ruby's own <tt>attr*</tt>
    # methods.
    #
    #   class Project < ActiveRecord::Base
    #     belongs_to              :portfolio
    #     has_one                 :project_manager
    #     has_many                :milestones
    #     has_and_belongs_to_many :categories
    #   end
    #
    # The project class now has the following methods (and more) to ease the traversal and
    # manipulation of its relationships:
    # * <tt>Project#portfolio, Project#portfolio=(portfolio), Project#portfolio.nil?</tt>
    # * <tt>Project#project_manager, Project#project_manager=(project_manager), Project#project_manager.nil?,</tt>
    # * <tt>Project#milestones.empty?, Project#milestones.size, Project#milestones, Project#milestones<<(milestone),</tt>
    #   <tt>Project#milestones.delete(milestone), Project#milestones.find(milestone_id), Project#milestones.all(options),</tt>
    #   <tt>Project#milestones.build, Project#milestones.create</tt>
    # * <tt>Project#categories.empty?, Project#categories.size, Project#categories, Project#categories<<(category1),</tt>
    #   <tt>Project#categories.delete(category1)</tt>
    #
    # === Overriding generated methods
    #
    # Association methods are generated in a module that is included into the model class,
    # which allows you to easily override with your own methods and call the original
    # generated method with +super+. For example:
    #
    #   class Car < ActiveRecord::Base
    #     belongs_to :owner
    #     belongs_to :old_owner
    #     def owner=(new_owner)
    #       self.old_owner = self.owner
    #       super
    #     end
    #   end
    #
    # If your model class is <tt>Project</tt>, the module is
    # named <tt>Project::GeneratedFeatureMethods</tt>. The GeneratedFeatureMethods module is
    # included in the model class immediately after the (anonymous) generated attributes methods
    # module, meaning an association will override the methods for an attribute with the same name.
    #
    # === A word of warning
    #
    # Don't create associations that have the same name as instance methods of
    # <tt>ActiveRecord::Base</tt>. Since the association adds a method with that name to
    # its model, it will override the inherited method and break things.
    # For instance, +attributes+ and +connection+ would be bad choices for association names.
    #
    # == Auto-generated methods
    #
    # === Singular associations (one-to-one)
    #                                     |            |  belongs_to  |
    #   generated methods                 | belongs_to | :polymorphic | has_one
    #   ----------------------------------+------------+--------------+---------
    #   other                             |     X      |      X       |    X
    #   other=(other)                     |     X      |      X       |    X
    #   build_other(attributes={})        |     X      |              |    X
    #   create_other(attributes={})       |     X      |              |    X
    #   create_other!(attributes={})      |     X      |              |    X
    #
    # ===Collection associations (one-to-many / many-to-many)
    #                                     |       |          | has_many
    #   generated methods                 | habtm | has_many | :through
    #   ----------------------------------+-------+----------+----------
    #   others                            |   X   |    X     |    X
    #   others=(other,other,...)          |   X   |    X     |    X
    #   other_ids                         |   X   |    X     |    X
    #   other_ids=(id,id,...)             |   X   |    X     |    X
    #   others<<                          |   X   |    X     |    X
    #   others.push                       |   X   |    X     |    X
    #   others.concat                     |   X   |    X     |    X
    #   others.build(attributes={})       |   X   |    X     |    X
    #   others.create(attributes={})      |   X   |    X     |    X
    #   others.create!(attributes={})     |   X   |    X     |    X
    #   others.size                       |   X   |    X     |    X
    #   others.length                     |   X   |    X     |    X
    #   others.count                      |   X   |    X     |    X
    #   others.sum(args*,&block)          |   X   |    X     |    X
    #   others.empty?                     |   X   |    X     |    X
    #   others.clear                      |   X   |    X     |    X
    #   others.delete(other,other,...)    |   X   |    X     |    X
    #   others.delete_all                 |   X   |    X     |    X
    #   others.destroy_all                |   X   |    X     |    X
    #   others.find(*args)                |   X   |    X     |    X
    #   others.exists?                    |   X   |    X     |    X
    #   others.uniq                       |   X   |    X     |    X
    #   others.reset                      |   X   |    X     |    X
    #
    # == Cardinality and associations
    #
    # Active Record associations can be used to describe one-to-one, one-to-many and many-to-many
    # relationships between models. Each model uses an association to describe its role in
    # the relation. The +belongs_to+ association is always used in the model that has
    # the foreign key.
    #
    # === One-to-one
    #
    # Use +has_one+ in the base, and +belongs_to+ in the associated model.
    #
    #   class Employee < ActiveRecord::Base
    #     has_one :office
    #   end
    #   class Office < ActiveRecord::Base
    #     belongs_to :employee    # foreign key - employee_id
    #   end
    #
    # === One-to-many
    #
    # Use +has_many+ in the base, and +belongs_to+ in the associated model.
    #
    #   class Manager < ActiveRecord::Base
    #     has_many :employees
    #   end
    #   class Employee < ActiveRecord::Base
    #     belongs_to :manager     # foreign key - manager_id
    #   end
    #
    # === Many-to-many
    #
    # There are two ways to build a many-to-many relationship.
    #
    # The first way uses a +has_many+ association with the <tt>:through</tt> option and a join model, so
    # there are two stages of associations.
    #
    #   class Assignment < ActiveRecord::Base
    #     belongs_to :programmer  # foreign key - programmer_id
    #     belongs_to :project     # foreign key - project_id
    #   end
    #   class Programmer < ActiveRecord::Base
    #     has_many :assignments
    #     has_many :projects, :through => :assignments
    #   end
    #   class Project < ActiveRecord::Base
    #     has_many :assignments
    #     has_many :programmers, :through => :assignments
    #   end
    #
    # For the second way, use +has_and_belongs_to_many+ in both models. This requires a join table
    # that has no corresponding model or primary key.
    #
    #   class Programmer < ActiveRecord::Base
    #     has_and_belongs_to_many :projects       # foreign keys in the join table
    #   end
    #   class Project < ActiveRecord::Base
    #     has_and_belongs_to_many :programmers    # foreign keys in the join table
    #   end
    #
    # Choosing which way to build a many-to-many relationship is not always simple.
    # If you need to work with the relationship model as its own entity,
    # use <tt>has_many :through</tt>. Use +has_and_belongs_to_many+ when working with legacy schemas or when
    # you never work directly with the relationship itself.
    #
    # == Is it a +belongs_to+ or +has_one+ association?
    #
    # Both express a 1-1 relationship. The difference is mostly where to place the foreign
    # key, which goes on the table for the class declaring the +belongs_to+ relationship.
    #
    #   class User < ActiveRecord::Base
    #     # I reference an account.
    #     belongs_to :account
    #   end
    #
    #   class Account < ActiveRecord::Base
    #     # One user references me.
    #     has_one :user
    #   end
    #
    # The tables for these classes could look something like:
    #
    #   CREATE TABLE users (
    #     id int(11) NOT NULL auto_increment,
    #     account_id int(11) default NULL,
    #     name varchar default NULL,
    #     PRIMARY KEY  (id)
    #   )
    #
    #   CREATE TABLE accounts (
    #     id int(11) NOT NULL auto_increment,
    #     name varchar default NULL,
    #     PRIMARY KEY  (id)
    #   )
    #
    # == Unsaved objects and associations
    #
    # You can manipulate objects and associations before they are saved to the database, but
    # there is some special behavior you should be aware of, mostly involving the saving of
    # associated objects.
    #
    # You can set the :autosave option on a <tt>has_one</tt>, <tt>belongs_to</tt>,
    # <tt>has_many</tt>, or <tt>has_and_belongs_to_many</tt> association. Setting it
    # to +true+ will _always_ save the members, whereas setting it to +false+ will
    # _never_ save the members. More details about :autosave option is available at
    # autosave_association.rb .
    #
    # === One-to-one associations
    #
    # * Assigning an object to a +has_one+ association automatically saves that object and
    #   the object being replaced (if there is one), in order to update their foreign
    #   keys - except if the parent object is unsaved (<tt>new_record? == true</tt>).
    # * If either of these saves fail (due to one of the objects being invalid), an
    #   <tt>ActiveRecord::RecordNotSaved</tt> exception is raised and the assignment is
    #   cancelled.
    # * If you wish to assign an object to a +has_one+ association without saving it,
    #   use the <tt>build_association</tt> method (documented below). The object being
    #   replaced will still be saved to update its foreign key.
    # * Assigning an object to a +belongs_to+ association does not save the object, since
    #   the foreign key field belongs on the parent. It does not save the parent either.
    #
    # === Collections
    #
    # * Adding an object to a collection (+has_many+ or +has_and_belongs_to_many+) automatically
    #   saves that object, except if the parent object (the owner of the collection) is not yet
    #   stored in the database.
    # * If saving any of the objects being added to a collection (via <tt>push</tt> or similar)
    #   fails, then <tt>push</tt> returns +false+.
    # * If saving fails while replacing the collection (via <tt>association=</tt>), an
    #   <tt>ActiveRecord::RecordNotSaved</tt> exception is raised and the assignment is
    #   cancelled.
    # * You can add an object to a collection without automatically saving it by using the
    #   <tt>collection.build</tt> method (documented below).
    # * All unsaved (<tt>new_record? == true</tt>) members of the collection are automatically
    #   saved when the parent is saved.
    #
    # === Association callbacks
    #
    # Similar to the normal callbacks that hook into the life cycle of an Active Record object,
    # you can also define callbacks that get triggered when you add an object to or remove an
    # object from an association collection.
    #
    #   class Project
    #     has_and_belongs_to_many :developers, :after_add => :evaluate_velocity
    #
    #     def evaluate_velocity(developer)
    #       ...
    #     end
    #   end
    #
    # It's possible to stack callbacks by passing them as an array. Example:
    #
    #   class Project
    #     has_and_belongs_to_many :developers,
    #                             :after_add => [:evaluate_velocity, Proc.new { |p, d| p.shipping_date = Time.now}]
    #   end
    #
    # Possible callbacks are: +before_add+, +after_add+, +before_remove+ and +after_remove+.
    #
    # Should any of the +before_add+ callbacks throw an exception, the object does not get
    # added to the collection. Same with the +before_remove+ callbacks; if an exception is
    # thrown the object doesn't get removed.
    #
    # === Association extensions
    #
    # The proxy objects that control the access to associations can be extended through anonymous
    # modules. This is especially beneficial for adding new finders, creators, and other
    # factory-type methods that are only used as part of this association.
    #
    #   class Account < ActiveRecord::Base
    #     has_many :people do
    #       def find_or_create_by_name(name)
    #         first_name, last_name = name.split(" ", 2)
    #         find_or_create_by_first_name_and_last_name(first_name, last_name)
    #       end
    #     end
    #   end
    #
    #   person = Account.first.people.find_or_create_by_name("David Heinemeier Hansson")
    #   person.first_name # => "David"
    #   person.last_name  # => "Heinemeier Hansson"
    #
    # If you need to share the same extensions between many associations, you can use a named
    # extension module.
    #
    #   module FindOrCreateByNameExtension
    #     def find_or_create_by_name(name)
    #       first_name, last_name = name.split(" ", 2)
    #       find_or_create_by_first_name_and_last_name(first_name, last_name)
    #     end
    #   end
    #
    #   class Account < ActiveRecord::Base
    #     has_many :people, :extend => FindOrCreateByNameExtension
    #   end
    #
    #   class Company < ActiveRecord::Base
    #     has_many :people, :extend => FindOrCreateByNameExtension
    #   end
    #
    # If you need to use multiple named extension modules, you can specify an array of modules
    # with the <tt>:extend</tt> option.
    # In the case of name conflicts between methods in the modules, methods in modules later
    # in the array supercede those earlier in the array.
    #
    #   class Account < ActiveRecord::Base
    #     has_many :people, :extend => [FindOrCreateByNameExtension, FindRecentExtension]
    #   end
    #
    # Some extensions can only be made to work with knowledge of the association's internals.
    # Extensions can access relevant state using the following methods (where +items+ is the
    # name of the association):
    #
    # * <tt>record.association(:items).owner</tt> - Returns the object the association is part of.
    # * <tt>record.association(:items).reflection</tt> - Returns the reflection object that describes the association.
    # * <tt>record.association(:items).target</tt> - Returns the associated object for +belongs_to+ and +has_one+, or
    #   the collection of associated objects for +has_many+ and +has_and_belongs_to_many+.
    #
    # However, inside the actual extension code, you will not have access to the <tt>record</tt> as
    # above. In this case, you can access <tt>proxy_association</tt>. For example,
    # <tt>record.association(:items)</tt> and <tt>record.items.proxy_association</tt> will return
    # the same object, allowing you to make calls like <tt>proxy_association.owner</tt> inside
    # association extensions.
    #
    # === Association Join Models
    #
    # Has Many associations can be configured with the <tt>:through</tt> option to use an
    # explicit join model to retrieve the data. This operates similarly to a
    # +has_and_belongs_to_many+ association. The advantage is that you're able to add validations,
    # callbacks, and extra attributes on the join model. Consider the following schema:
    #
    #   class Author < ActiveRecord::Base
    #     has_many :authorships
    #     has_many :books, :through => :authorships
    #   end
    #
    #   class Authorship < ActiveRecord::Base
    #     belongs_to :author
    #     belongs_to :book
    #   end
    #
    #   @author = Author.first
    #   @author.authorships.collect { |a| a.book } # selects all books that the author's authorships belong to
    #   @author.books                              # selects all books by using the Authorship join model
    #
    # You can also go through a +has_many+ association on the join model:
    #
    #   class Firm < ActiveRecord::Base
    #     has_many   :clients
    #     has_many   :invoices, :through => :clients
    #   end
    #
    #   class Client < ActiveRecord::Base
    #     belongs_to :firm
    #     has_many   :invoices
    #   end
    #
    #   class Invoice < ActiveRecord::Base
    #     belongs_to :client
    #   end
    #
    #   @firm = Firm.first
    #   @firm.clients.collect { |c| c.invoices }.flatten # select all invoices for all clients of the firm
    #   @firm.invoices                                   # selects all invoices by going through the Client join model
    #
    # Similarly you can go through a +has_one+ association on the join model:
    #
    #   class Group < ActiveRecord::Base
    #     has_many   :users
    #     has_many   :avatars, :through => :users
    #   end
    #
    #   class User < ActiveRecord::Base
    #     belongs_to :group
    #     has_one    :avatar
    #   end
    #
    #   class Avatar < ActiveRecord::Base
    #     belongs_to :user
    #   end
    #
    #   @group = Group.first
    #   @group.users.collect { |u| u.avatar }.flatten # select all avatars for all users in the group
    #   @group.avatars                                # selects all avatars by going through the User join model.
    #
    # An important caveat with going through +has_one+ or +has_many+ associations on the
    # join model is that these associations are *read-only*. For example, the following
    # would not work following the previous example:
    #
    #   @group.avatars << Avatar.new   # this would work if User belonged_to Avatar rather than the other way around
    #   @group.avatars.delete(@group.avatars.last)  # so would this
    #
    # If you are using a +belongs_to+ on the join model, it is a good idea to set the
    # <tt>:inverse_of</tt> option on the +belongs_to+, which will mean that the following example
    # works correctly (where <tt>tags</tt> is a +has_many+ <tt>:through</tt> association):
    #
    #   @post = Post.first
    #   @tag = @post.tags.build :name => "ruby"
    #   @tag.save
    #
    # The last line ought to save the through record (a <tt>Taggable</tt>). This will only work if the
    # <tt>:inverse_of</tt> is set:
    #
    #   class Taggable < ActiveRecord::Base
    #     belongs_to :post
    #     belongs_to :tag, :inverse_of => :taggings
    #   end
    #
    # === Nested Associations
    #
    # You can actually specify *any* association with the <tt>:through</tt> option, including an
    # association which has a <tt>:through</tt> option itself. For example:
    #
    #   class Author < ActiveRecord::Base
    #     has_many :posts
    #     has_many :comments, :through => :posts
    #     has_many :commenters, :through => :comments
    #   end
    #
    #   class Post < ActiveRecord::Base
    #     has_many :comments
    #   end
    #
    #   class Comment < ActiveRecord::Base
    #     belongs_to :commenter
    #   end
    #
    #   @author = Author.first
    #   @author.commenters # => People who commented on posts written by the author
    #
    # An equivalent way of setting up this association this would be:
    #
    #   class Author < ActiveRecord::Base
    #     has_many :posts
    #     has_many :commenters, :through => :posts
    #   end
    #
    #   class Post < ActiveRecord::Base
    #     has_many :comments
    #     has_many :commenters, :through => :comments
    #   end
    #
    #   class Comment < ActiveRecord::Base
    #     belongs_to :commenter
    #   end
    #
    # When using nested association, you will not be able to modify the association because there
    # is not enough information to know what modification to make. For example, if you tried to
    # add a <tt>Commenter</tt> in the example above, there would be no way to tell how to set up the
    # intermediate <tt>Post</tt> and <tt>Comment</tt> objects.
    #
    # === Polymorphic Associations
    #
    # Polymorphic associations on models are not restricted on what types of models they
    # can be associated with. Rather, they specify an interface that a +has_many+ association
    # must adhere to.
    #
    #   class Asset < ActiveRecord::Base
    #     belongs_to :attachable, :polymorphic => true
    #   end
    #
    #   class Post < ActiveRecord::Base
    #     has_many :assets, :as => :attachable         # The :as option specifies the polymorphic interface to use.
    #   end
    #
    #   @asset.attachable = @post
    #
    # This works by using a type column in addition to a foreign key to specify the associated
    # record. In the Asset example, you'd need an +attachable_id+ integer column and an
    # +attachable_type+ string column.
    #
    # Using polymorphic associations in combination with single table inheritance (STI) is
    # a little tricky. In order for the associations to work as expected, ensure that you
    # store the base model for the STI models in the type column of the polymorphic
    # association. To continue with the asset example above, suppose there are guest posts
    # and member posts that use the posts table for STI. In this case, there must be a +type+
    # column in the posts table.
    #
    #   class Asset < ActiveRecord::Base
    #     belongs_to :attachable, :polymorphic => true
    #
    #     def attachable_type=(sType)
    #        super(sType.to_s.classify.constantize.base_class.to_s)
    #     end
    #   end
    #
    #   class Post < ActiveRecord::Base
    #     # because we store "Post" in attachable_type now :dependent => :destroy will work
    #     has_many :assets, :as => :attachable, :dependent => :destroy
    #   end
    #
    #   class GuestPost < Post
    #   end
    #
    #   class MemberPost < Post
    #   end
    #
    # == Caching
    #
    # All of the methods are built on a simple caching principle that will keep the result
    # of the last query around unless specifically instructed not to. The cache is even
    # shared across methods to make it even cheaper to use the macro-added methods without
    # worrying too much about performance at the first go.
    #
    #   project.milestones             # fetches milestones from the database
    #   project.milestones.size        # uses the milestone cache
    #   project.milestones.empty?      # uses the milestone cache
    #   project.milestones(true).size  # fetches milestones from the database
    #   project.milestones             # uses the milestone cache
    #
    # == Eager loading of associations
    #
    # Eager loading is a way to find objects of a certain class and a number of named associations.
    # This is one of the easiest ways of to prevent the dreaded 1+N problem in which fetching 100
    # posts that each need to display their author triggers 101 database queries. Through the
    # use of eager loading, the 101 queries can be reduced to 2.
    #
    #   class Post < ActiveRecord::Base
    #     belongs_to :author
    #     has_many   :comments
    #   end
    #
    # Consider the following loop using the class above:
    #
    #   Post.all.each do |post|
    #     puts "Post:            " + post.title
    #     puts "Written by:      " + post.author.name
    #     puts "Last comment on: " + post.comments.first.created_on
    #   end
    #
    # To iterate over these one hundred posts, we'll generate 201 database queries. Let's
    # first just optimize it for retrieving the author:
    #
    #   Post.includes(:author).each do |post|
    #
    # This references the name of the +belongs_to+ association that also used the <tt>:author</tt>
    # symbol. After loading the posts, find will collect the +author_id+ from each one and load
    # all the referenced authors with one query. Doing so will cut down the number of queries
    # from 201 to 102.
    #
    # We can improve upon the situation further by referencing both associations in the finder with:
    #
    #   Post.includes(:author, :comments).each do |post|
    #
    # This will load all comments with a single query. This reduces the total number of queries
    # to 3. More generally the number of queries will be 1 plus the number of associations
    # named (except if some of the associations are polymorphic +belongs_to+ - see below).
    #
    # To include a deep hierarchy of associations, use a hash:
    #
    #   Post.includes(:author, {:comments => {:author => :gravatar}}).each do |post|
    #
    # That'll grab not only all the comments but all their authors and gravatar pictures.
    # You can mix and match symbols, arrays and hashes in any combination to describe the
    # associations you want to load.
    #
    # All of this power shouldn't fool you into thinking that you can pull out huge amounts
    # of data with no performance penalty just because you've reduced the number of queries.
    # The database still needs to send all the data to Active Record and it still needs to
    # be processed. So it's no catch-all for performance problems, but it's a great way to
    # cut down on the number of queries in a situation as the one described above.
    #
    # Since only one table is loaded at a time, conditions or orders cannot reference tables
    # other than the main one. If this is the case Active Record falls back to the previously
    # used LEFT OUTER JOIN based strategy. For example
    #
    #   Post.includes([:author, :comments]).where(['comments.approved = ?', true]).all
    #
    # This will result in a single SQL query with joins along the lines of:
    # <tt>LEFT OUTER JOIN comments ON comments.post_id = posts.id</tt> and
    # <tt>LEFT OUTER JOIN authors ON authors.id = posts.author_id</tt>. Note that using conditions
    # like this can have unintended consequences.
    # In the above example posts with no approved comments are not returned at all, because
    # the conditions apply to the SQL statement as a whole and not just to the association.
    # You must disambiguate column references for this fallback to happen, for example
    # <tt>:order => "author.name DESC"</tt> will work but <tt>:order => "name DESC"</tt> will not.
    #
    # If you do want eager load only some members of an association it is usually more natural
    # to include an association which has conditions defined on it:
    #
    #   class Post < ActiveRecord::Base
    #     has_many :approved_comments, :class_name => 'Comment', :conditions => ['approved = ?', true]
    #   end
    #
    #   Post.includes(:approved_comments)
    #
    # This will load posts and eager load the +approved_comments+ association, which contains
    # only those comments that have been approved.
    #
    # If you eager load an association with a specified <tt>:limit</tt> option, it will be ignored,
    # returning all the associated objects:
    #
    #   class Picture < ActiveRecord::Base
    #     has_many :most_recent_comments, :class_name => 'Comment', :order => 'id DESC', :limit => 10
    #   end
    #
    #   Picture.includes(:most_recent_comments).first.most_recent_comments # => returns all associated comments.
    #
    # When eager loaded, conditions are interpolated in the context of the model class, not
    # the model instance. Conditions are lazily interpolated before the actual model exists.
    #
    # Eager loading is supported with polymorphic associations.
    #
    #   class Address < ActiveRecord::Base
    #     belongs_to :addressable, :polymorphic => true
    #   end
    #
    # A call that tries to eager load the addressable model
    #
    #   Address.includes(:addressable)
    #
    # This will execute one query to load the addresses and load the addressables with one
    # query per addressable type.
    # For example if all the addressables are either of class Person or Company then a total
    # of 3 queries will be executed. The list of addressable types to load is determined on
    # the back of the addresses loaded. This is not supported if Active Record has to fallback
    # to the previous implementation of eager loading and will raise ActiveRecord::EagerLoadPolymorphicError.
    # The reason is that the parent model's type is a column value so its corresponding table
    # name cannot be put in the +FROM+/+JOIN+ clauses of that query.
    #
    # == Table Aliasing
    #
    # Active Record uses table aliasing in the case that a table is referenced multiple times
    # in a join. If a table is referenced only once, the standard table name is used. The
    # second time, the table is aliased as <tt>#{reflection_name}_#{parent_table_name}</tt>.
    # Indexes are appended for any more successive uses of the table name.
    #
    #   Post.joins(:comments)
    #   # => SELECT ... FROM posts INNER JOIN comments ON ...
    #   Post.joins(:special_comments) # STI
    #   # => SELECT ... FROM posts INNER JOIN comments ON ... AND comments.type = 'SpecialComment'
    #   Post.joins(:comments, :special_comments) # special_comments is the reflection name, posts is the parent table name
    #   # => SELECT ... FROM posts INNER JOIN comments ON ... INNER JOIN comments special_comments_posts
    #
    # Acts as tree example:
    #
    #   TreeMixin.joins(:children)
    #   # => SELECT ... FROM mixins INNER JOIN mixins childrens_mixins ...
    #   TreeMixin.joins(:children => :parent)
    #   # => SELECT ... FROM mixins INNER JOIN mixins childrens_mixins ...
    #                               INNER JOIN parents_mixins ...
    #   TreeMixin.joins(:children => {:parent => :children})
    #   # => SELECT ... FROM mixins INNER JOIN mixins childrens_mixins ...
    #                               INNER JOIN parents_mixins ...
    #                               INNER JOIN mixins childrens_mixins_2
    #
    # Has and Belongs to Many join tables use the same idea, but add a <tt>_join</tt> suffix:
    #
    #   Post.joins(:categories)
    #   # => SELECT ... FROM posts INNER JOIN categories_posts ... INNER JOIN categories ...
    #   Post.joins(:categories => :posts)
    #   # => SELECT ... FROM posts INNER JOIN categories_posts ... INNER JOIN categories ...
    #                              INNER JOIN categories_posts posts_categories_join INNER JOIN posts posts_categories
    #   Post.joins(:categories => {:posts => :categories})
    #   # => SELECT ... FROM posts INNER JOIN categories_posts ... INNER JOIN categories ...
    #                              INNER JOIN categories_posts posts_categories_join INNER JOIN posts posts_categories
    #                              INNER JOIN categories_posts categories_posts_join INNER JOIN categories categories_posts_2
    #
    # If you wish to specify your own custom joins using <tt>joins</tt> method, those table
    # names will take precedence over the eager associations:
    #
    #   Post.joins(:comments).joins("inner join comments ...")
    #   # => SELECT ... FROM posts INNER JOIN comments_posts ON ... INNER JOIN comments ...
    #   Post.joins(:comments, :special_comments).joins("inner join comments ...")
    #   # => SELECT ... FROM posts INNER JOIN comments comments_posts ON ...
    #                              INNER JOIN comments special_comments_posts ...
    #                              INNER JOIN comments ...
    #
    # Table aliases are automatically truncated according to the maximum length of table identifiers
    # according to the specific database.
    #
    # == Modules
    #
    # By default, associations will look for objects within the current module scope. Consider:
    #
    #   module MyApplication
    #     module Business
    #       class Firm < ActiveRecord::Base
    #          has_many :clients
    #        end
    #
    #       class Client < ActiveRecord::Base; end
    #     end
    #   end
    #
    # When <tt>Firm#clients</tt> is called, it will in turn call
    # <tt>MyApplication::Business::Client.find_all_by_firm_id(firm.id)</tt>.
    # If you want to associate with a class in another module scope, this can be done by
    # specifying the complete class name.
    #
    #   module MyApplication
    #     module Business
    #       class Firm < ActiveRecord::Base; end
    #     end
    #
    #     module Billing
    #       class Account < ActiveRecord::Base
    #         belongs_to :firm, :class_name => "MyApplication::Business::Firm"
    #       end
    #     end
    #   end
    #
    # == Bi-directional associations
    #
    # When you specify an association there is usually an association on the associated model
    # that specifies the same relationship in reverse. For example, with the following models:
    #
    #    class Dungeon < ActiveRecord::Base
    #      has_many :traps
    #      has_one :evil_wizard
    #    end
    #
    #    class Trap < ActiveRecord::Base
    #      belongs_to :dungeon
    #    end
    #
    #    class EvilWizard < ActiveRecord::Base
    #      belongs_to :dungeon
    #    end
    #
    # The +traps+ association on +Dungeon+ and the +dungeon+ association on +Trap+ are
    # the inverse of each other and the inverse of the +dungeon+ association on +EvilWizard+
    # is the +evil_wizard+ association on +Dungeon+ (and vice-versa). By default,
    # Active Record doesn't know anything about these inverse relationships and so no object
    # loading optimization is possible. For example:
    #
    #    d = Dungeon.first
    #    t = d.traps.first
    #    d.level == t.dungeon.level # => true
    #    d.level = 10
    #    d.level == t.dungeon.level # => false
    #
    # The +Dungeon+ instances +d+ and <tt>t.dungeon</tt> in the above example refer to
    # the same object data from the database, but are actually different in-memory copies
    # of that data. Specifying the <tt>:inverse_of</tt> option on associations lets you tell
    # Active Record about inverse relationships and it will optimise object loading. For
    # example, if we changed our model definitions to:
    #
    #    class Dungeon < ActiveRecord::Base
    #      has_many :traps, :inverse_of => :dungeon
    #      has_one :evil_wizard, :inverse_of => :dungeon
    #    end
    #
    #    class Trap < ActiveRecord::Base
    #      belongs_to :dungeon, :inverse_of => :traps
    #    end
    #
    #    class EvilWizard < ActiveRecord::Base
    #      belongs_to :dungeon, :inverse_of => :evil_wizard
    #    end
    #
    # Then, from our code snippet above, +d+ and <tt>t.dungeon</tt> are actually the same
    # in-memory instance and our final <tt>d.level == t.dungeon.level</tt> will return +true+.
    #
    # There are limitations to <tt>:inverse_of</tt> support:
    #
    # * does not work with <tt>:through</tt> associations.
    # * does not work with <tt>:polymorphic</tt> associations.
    # * for +belongs_to+ associations +has_many+ inverse associations are ignored.
    #
    # == Deleting from associations
    #
    # === Dependent associations
    #
    # +has_many+, +has_one+ and +belongs_to+ associations support the <tt>:dependent</tt> option.
    # This allows you to specify that associated records should be deleted when the owner is
    # deleted.
    #
    # For example:
    #
    #     class Author
    #       has_many :posts, :dependent => :destroy
    #     end
    #     Author.find(1).destroy # => Will destroy all of the author's posts, too
    #
    # The <tt>:dependent</tt> option can have different values which specify how the deletion
    # is done. For more information, see the documentation for this option on the different
    # specific association types.
    #
    # === Delete or destroy?
    #
    # +has_many+ and +has_and_belongs_to_many+ associations have the methods <tt>destroy</tt>,
    # <tt>delete</tt>, <tt>destroy_all</tt> and <tt>delete_all</tt>.
    #
    # For +has_and_belongs_to_many+, <tt>delete</tt> and <tt>destroy</tt> are the same: they
    # cause the records in the join table to be removed.
    #
    # For +has_many+, <tt>destroy</tt> will always call the <tt>destroy</tt> method of the
    # record(s) being removed so that callbacks are run. However <tt>delete</tt> will either
    # do the deletion according to the strategy specified by the <tt>:dependent</tt> option, or
    # if no <tt>:dependent</tt> option is given, then it will follow the default strategy.
    # The default strategy is <tt>:nullify</tt> (set the foreign keys to <tt>nil</tt>), except for
    # +has_many+ <tt>:through</tt>, where the default strategy is <tt>delete_all</tt> (delete
    # the join records, without running their callbacks).
    #
    # There is also a <tt>clear</tt> method which is the same as <tt>delete_all</tt>, except that
    # it returns the association rather than the records which have been deleted.
    #
    # === What gets deleted?
    #
    # There is a potential pitfall here: +has_and_belongs_to_many+ and +has_many+ <tt>:through</tt>
    # associations have records in join tables, as well as the associated records. So when we
    # call one of these deletion methods, what exactly should be deleted?
    #
    # The answer is that it is assumed that deletion on an association is about removing the
    # <i>link</i> between the owner and the associated object(s), rather than necessarily the
    # associated objects themselves. So with +has_and_belongs_to_many+ and +has_many+
    # <tt>:through</tt>, the join records will be deleted, but the associated records won't.
    #
    # This makes sense if you think about it: if you were to call <tt>post.tags.delete(Tag.find_by_name('food'))</tt>
    # you would want the 'food' tag to be unlinked from the post, rather than for the tag itself
    # to be removed from the database.
    #
    # However, there are examples where this strategy doesn't make sense. For example, suppose
    # a person has many projects, and each project has many tasks. If we deleted one of a person's
    # tasks, we would probably not want the project to be deleted. In this scenario, the delete method
    # won't actually work: it can only be used if the association on the join model is a
    # +belongs_to+. In other situations you are expected to perform operations directly on
    # either the associated records or the <tt>:through</tt> association.
    #
    # With a regular +has_many+ there is no distinction between the "associated records"
    # and the "link", so there is only one choice for what gets deleted.
    #
    # With +has_and_belongs_to_many+ and +has_many+ <tt>:through</tt>, if you want to delete the
    # associated records themselves, you can always do something along the lines of
    # <tt>person.tasks.each(&:destroy)</tt>.
    #
    # == Type safety with <tt>ActiveRecord::AssociationTypeMismatch</tt>
    #
    # If you attempt to assign an object to an association that doesn't match the inferred
    # or specified <tt>:class_name</tt>, you'll get an <tt>ActiveRecord::AssociationTypeMismatch</tt>.
    #
    # == Options
    #
    # All of the association macros can be specialized through options. This makes cases
    # more complex than the simple and guessable ones possible.
    module ClassMethods
      # Specifies a one-to-many association. The following methods for retrieval and query of
      # collections of associated objects will be added:
      #
      # [collection(force_reload = false)]
      #   Returns an array of all the associated objects.
      #   An empty array is returned if none are found.
      # [collection<<(object, ...)]
      #   Adds one or more objects to the collection by setting their foreign keys to the collection's primary key.
      #   Note that this operation instantly fires update sql without waiting for the save or update call on the
      #   parent object.
      # [collection.delete(object, ...)]
      #   Removes one or more objects from the collection by setting their foreign keys to +NULL+.
      #   Objects will be in addition destroyed if they're associated with <tt>:dependent => :destroy</tt>,
      #   and deleted if they're associated with <tt>:dependent => :delete_all</tt>.
      #
      #   If the <tt>:through</tt> option is used, then the join records are deleted (rather than
      #   nullified) by default, but you can specify <tt>:dependent => :destroy</tt> or
      #   <tt>:dependent => :nullify</tt> to override this.
      # [collection=objects]
      #   Replaces the collections content by deleting and adding objects as appropriate. If the <tt>:through</tt>
      #   option is true callbacks in the join models are triggered except destroy callbacks, since deletion is
      #   direct.
      # [collection_singular_ids]
      #   Returns an array of the associated objects' ids
      # [collection_singular_ids=ids]
      #   Replace the collection with the objects identified by the primary keys in +ids+. This
      #   method loads the models and calls <tt>collection=</tt>. See above.
      # [collection.clear]
      #   Removes every object from the collection. This destroys the associated objects if they
      #   are associated with <tt>:dependent => :destroy</tt>, deletes them directly from the
      #   database if <tt>:dependent => :delete_all</tt>, otherwise sets their foreign keys to +NULL+.
      #   If the <tt>:through</tt> option is true no destroy callbacks are invoked on the join models.
      #   Join models are directly deleted.
      # [collection.empty?]
      #   Returns +true+ if there are no associated objects.
      # [collection.size]
      #   Returns the number of associated objects.
      # [collection.find(...)]
      #   Finds an associated object according to the same rules as ActiveRecord::Base.find.
      # [collection.exists?(...)]
      #   Checks whether an associated object with the given conditions exists.
      #   Uses the same rules as ActiveRecord::Base.exists?.
      # [collection.build(attributes = {}, ...)]
      #   Returns one or more new objects of the collection type that have been instantiated
      #   with +attributes+ and linked to this object through a foreign key, but have not yet
      #   been saved.
      # [collection.create(attributes = {})]
      #   Returns a new object of the collection type that has been instantiated
      #   with +attributes+, linked to this object through a foreign key, and that has already
      #   been saved (if it passed the validation). *Note*: This only works if the base model
      #   already exists in the DB, not if it is a new (unsaved) record!
      #
      # (*Note*: +collection+ is replaced with the symbol passed as the first argument, so
      # <tt>has_many :clients</tt> would add among others <tt>clients.empty?</tt>.)
      #
      # === Example
      #
      # Example: A Firm class declares <tt>has_many :clients</tt>, which will add:
      # * <tt>Firm#clients</tt> (similar to <tt>Clients.all :conditions => ["firm_id = ?", id]</tt>)
      # * <tt>Firm#clients<<</tt>
      # * <tt>Firm#clients.delete</tt>
      # * <tt>Firm#clients=</tt>
      # * <tt>Firm#client_ids</tt>
      # * <tt>Firm#client_ids=</tt>
      # * <tt>Firm#clients.clear</tt>
      # * <tt>Firm#clients.empty?</tt> (similar to <tt>firm.clients.size == 0</tt>)
      # * <tt>Firm#clients.size</tt> (similar to <tt>Client.count "firm_id = #{id}"</tt>)
      # * <tt>Firm#clients.find</tt> (similar to <tt>Client.find(id, :conditions => "firm_id = #{id}")</tt>)
      # * <tt>Firm#clients.exists?(:name => 'ACME')</tt> (similar to <tt>Client.exists?(:name => 'ACME', :firm_id => firm.id)</tt>)
      # * <tt>Firm#clients.build</tt> (similar to <tt>Client.new("firm_id" => id)</tt>)
      # * <tt>Firm#clients.create</tt> (similar to <tt>c = Client.new("firm_id" => id); c.save; c</tt>)
      # The declaration can also include an options hash to specialize the behavior of the association.
      #
      # === Options
      # [:class_name]
      #   Specify the class name of the association. Use it only if that name can't be inferred
      #   from the association name. So <tt>has_many :products</tt> will by default be linked
      #   to the Product class, but if the real class name is SpecialProduct, you'll have to
      #   specify it with this option.
      # [:conditions]
      #   Specify the conditions that the associated objects must meet in order to be included as a +WHERE+
      #   SQL fragment, such as <tt>price > 5 AND name LIKE 'B%'</tt>. Record creations from
      #   the association are scoped if a hash is used.
      #   <tt>has_many :posts, :conditions => {:published => true}</tt> will create published
      #   posts with <tt>@blog.posts.create</tt> or <tt>@blog.posts.build</tt>.
      # [:order]
      #   Specify the order in which the associated objects are returned as an <tt>ORDER BY</tt> SQL fragment,
      #   such as <tt>last_name, first_name DESC</tt>.
      # [:foreign_key]
      #   Specify the foreign key used for the association. By default this is guessed to be the name
      #   of this class in lower-case and "_id" suffixed. So a Person class that makes a +has_many+
      #   association will use "person_id" as the default <tt>:foreign_key</tt>.
      # [:primary_key]
      #   Specify the method that returns the primary key used for the association. By default this is +id+.
      # [:dependent]
      #   If set to <tt>:destroy</tt> all the associated objects are destroyed
      #   alongside this object by calling their +destroy+ method. If set to <tt>:delete_all</tt> all associated
      #   objects are deleted *without* calling their +destroy+ method. If set to <tt>:nullify</tt> all associated
      #   objects' foreign keys are set to +NULL+ *without* calling their +save+ callbacks. If set to
      #   <tt>:restrict</tt> this object raises an <tt>ActiveRecord::DeleteRestrictionError</tt> exception and
      #   cannot be deleted if it has any associated objects.
      #
      #   If using with the <tt>:through</tt> option, the association on the join model must be
      #   a +belongs_to+, and the records which get deleted are the join records, rather than
      #   the associated records.
      #
      # [:finder_sql]
      #   Specify a complete SQL statement to fetch the association. This is a good way to go for complex
      #   associations that depend on multiple tables. May be supplied as a string or a proc where interpolation is
      #   required. Note: When this option is used, +find_in_collection+
      #   is _not_ added.
      # [:counter_sql]
      #   Specify a complete SQL statement to fetch the size of the association. If <tt>:finder_sql</tt> is
      #   specified but not <tt>:counter_sql</tt>, <tt>:counter_sql</tt> will be generated by
      #   replacing <tt>SELECT ... FROM</tt> with <tt>SELECT COUNT(*) FROM</tt>.
      # [:extend]
      #   Specify a named module for extending the proxy. See "Association extensions".
      # [:include]
      #   Specify second-order associations that should be eager loaded when the collection is loaded.
      # [:group]
      #   An attribute name by which the result should be grouped. Uses the <tt>GROUP BY</tt> SQL-clause.
      # [:having]
      #   Combined with +:group+ this can be used to filter the records that a <tt>GROUP BY</tt>
      #   returns. Uses the <tt>HAVING</tt> SQL-clause.
      # [:limit]
      #   An integer determining the limit on the number of rows that should be returned.
      # [:offset]
      #   An integer determining the offset from where the rows should be fetched. So at 5,
      #   it would skip the first 4 rows.
      # [:select]
      #   By default, this is <tt>*</tt> as in <tt>SELECT * FROM</tt>, but can be changed if
      #   you, for example, want to do a join but not include the joined columns. Do not forget
      #   to include the primary and foreign keys, otherwise it will raise an error.
      # [:as]
      #   Specifies a polymorphic interface (See <tt>belongs_to</tt>).
      # [:through]
      #   Specifies an association through which to perform the query. This can be any other type
      #   of association, including other <tt>:through</tt> associations. Options for <tt>:class_name</tt>,
      #   <tt>:primary_key</tt> and <tt>:foreign_key</tt> are ignored, as the association uses the
      #   source reflection.
      #
      #   If the association on the join model is a +belongs_to+, the collection can be modified
      #   and the records on the <tt>:through</tt> model will be automatically created and removed
      #   as appropriate. Otherwise, the collection is read-only, so you should manipulate the
      #   <tt>:through</tt> association directly.
      #
      #   If you are going to modify the association (rather than just read from it), then it is
      #   a good idea to set the <tt>:inverse_of</tt> option on the source association on the
      #   join model. This allows associated records to be built which will automatically create
      #   the appropriate join model records when they are saved. (See the 'Association Join Models'
      #   section above.)
      # [:source]
      #   Specifies the source association name used by <tt>has_many :through</tt> queries.
      #   Only use it if the name cannot be inferred from the association.
      #   <tt>has_many :subscribers, :through => :subscriptions</tt> will look for either <tt>:subscribers</tt> or
      #   <tt>:subscriber</tt> on Subscription, unless a <tt>:source</tt> is given.
      # [:source_type]
      #   Specifies type of the source association used by <tt>has_many :through</tt> queries where the source
      #   association is a polymorphic +belongs_to+.
      # [:uniq]
      #   If true, duplicates will be omitted from the collection. Useful in conjunction with <tt>:through</tt>.
      # [:readonly]
      #   If true, all the associated objects are readonly through the association.
      # [:validate]
      #   If +false+, don't validate the associated objects when saving the parent object. true by default.
      # [:autosave]
      #   If true, always save the associated objects or destroy them if marked for destruction,
      #   when saving the parent object. If false, never save or destroy the associated objects.
      #   By default, only save associated objects that are new records.
      # [:inverse_of]
      #   Specifies the name of the <tt>belongs_to</tt> association on the associated object
      #   that is the inverse of this <tt>has_many</tt> association. Does not work in combination
      #   with <tt>:through</tt> or <tt>:as</tt> options.
      #   See ActiveRecord::Associations::ClassMethods's overview on Bi-directional associations for more detail.
      #
      # Option examples:
      #   has_many :comments, :order => "posted_on"
      #   has_many :comments, :include => :author
      #   has_many :people, :class_name => "Person", :conditions => "deleted = 0", :order => "name"
      #   has_many :tracks, :order => "position", :dependent => :destroy
      #   has_many :comments, :dependent => :nullify
      #   has_many :tags, :as => :taggable
      #   has_many :reports, :readonly => true
      #   has_many :subscribers, :through => :subscriptions, :source => :user
      #   has_many :subscribers, :class_name => "Person", :finder_sql => Proc.new {
      #       %Q{
      #         SELECT DISTINCT *
      #         FROM people p, post_subscriptions ps
      #         WHERE ps.post_id = #{id} AND ps.person_id = p.id
      #         ORDER BY p.first_name
      #       }
      #   }
      def has_many(name, options = {}, &extension)
        Builder::HasMany.build(self, name, options, &extension)
      end

      # Specifies a one-to-one association with another class. This method should only be used
      # if the other class contains the foreign key. If the current class contains the foreign key,
      # then you should use +belongs_to+ instead. See also ActiveRecord::Associations::ClassMethods's overview
      # on when to use has_one and when to use belongs_to.
      #
      # The following methods for retrieval and query of a single associated object will be added:
      #
      # [association(force_reload = false)]
      #   Returns the associated object. +nil+ is returned if none is found.
      # [association=(associate)]
      #   Assigns the associate object, extracts the primary key, sets it as the foreign key,
      #   and saves the associate object.
      # [build_association(attributes = {})]
      #   Returns a new object of the associated type that has been instantiated
      #   with +attributes+ and linked to this object through a foreign key, but has not
      #   yet been saved.
      # [create_association(attributes = {})]
      #   Returns a new object of the associated type that has been instantiated
      #   with +attributes+, linked to this object through a foreign key, and that
      #   has already been saved (if it passed the validation).
      # [create_association!(attributes = {})]
      #   Does the same as <tt>create_association</tt>, but raises <tt>ActiveRecord::RecordInvalid</tt>
      #   if the record is invalid.
      #
      # (+association+ is replaced with the symbol passed as the first argument, so
      # <tt>has_one :manager</tt> would add among others <tt>manager.nil?</tt>.)
      #
      # === Example
      #
      # An Account class declares <tt>has_one :beneficiary</tt>, which will add:
      # * <tt>Account#beneficiary</tt> (similar to <tt>Beneficiary.first(:conditions => "account_id = #{id}")</tt>)
      # * <tt>Account#beneficiary=(beneficiary)</tt> (similar to <tt>beneficiary.account_id = account.id; beneficiary.save</tt>)
      # * <tt>Account#build_beneficiary</tt> (similar to <tt>Beneficiary.new("account_id" => id)</tt>)
      # * <tt>Account#create_beneficiary</tt> (similar to <tt>b = Beneficiary.new("account_id" => id); b.save; b</tt>)
      # * <tt>Account#create_beneficiary!</tt> (similar to <tt>b = Beneficiary.new("account_id" => id); b.save!; b</tt>)
      #
      # === Options
      #
      # The declaration can also include an options hash to specialize the behavior of the association.
      #
      # Options are:
      # [:class_name]
      #   Specify the class name of the association. Use it only if that name can't be inferred
      #   from the association name. So <tt>has_one :manager</tt> will by default be linked to the Manager class, but
      #   if the real class name is Person, you'll have to specify it with this option.
      # [:conditions]
      #   Specify the conditions that the associated object must meet in order to be included as a +WHERE+
      #   SQL fragment, such as <tt>rank = 5</tt>. Record creation from the association is scoped if a hash
      #   is used. <tt>has_one :account, :conditions => {:enabled => true}</tt> will create
      #   an enabled account with <tt>@company.create_account</tt> or <tt>@company.build_account</tt>.
      # [:order]
      #   Specify the order in which the associated objects are returned as an <tt>ORDER BY</tt> SQL fragment,
      #   such as <tt>last_name, first_name DESC</tt>.
      # [:dependent]
      #   If set to <tt>:destroy</tt>, the associated object is destroyed when this object is. If set to
      #   <tt>:delete</tt>, the associated object is deleted *without* calling its destroy method.
      #   If set to <tt>:nullify</tt>, the associated object's foreign key is set to +NULL+.
      #   Also, association is assigned. If set to <tt>:restrict</tt> this object raises an
      #   <tt>ActiveRecord::DeleteRestrictionError</tt> exception and cannot be deleted if it has any associated object.
      # [:foreign_key]
      #   Specify the foreign key used for the association. By default this is guessed to be the name
      #   of this class in lower-case and "_id" suffixed. So a Person class that makes a +has_one+ association
      #   will use "person_id" as the default <tt>:foreign_key</tt>.
      # [:primary_key]
      #   Specify the method that returns the primary key used for the association. By default this is +id+.
      # [:include]
      #   Specify second-order associations that should be eager loaded when this object is loaded.
      # [:as]
      #   Specifies a polymorphic interface (See <tt>belongs_to</tt>).
      # [:select]
      #   By default, this is <tt>*</tt> as in <tt>SELECT * FROM</tt>, but can be changed if, for example,
      #   you want to do a join but not include the joined columns. Do not forget to include the
      #   primary and foreign keys, otherwise it will raise an error.
      # [:through]
      #   Specifies a Join Model through which to perform the query. Options for <tt>:class_name</tt>,
      #   <tt>:primary_key</tt>, and <tt>:foreign_key</tt> are ignored, as the association uses the
      #   source reflection. You can only use a <tt>:through</tt> query through a <tt>has_one</tt>
      #   or <tt>belongs_to</tt> association on the join model.
      # [:source]
      #   Specifies the source association name used by <tt>has_one :through</tt> queries.
      #   Only use it if the name cannot be inferred from the association.
      #   <tt>has_one :favorite, :through => :favorites</tt> will look for a
      #   <tt>:favorite</tt> on Favorite, unless a <tt>:source</tt> is given.
      # [:source_type]
      #   Specifies type of the source association used by <tt>has_one :through</tt> queries where the source
      #   association is a polymorphic +belongs_to+.
      # [:readonly]
      #   If true, the associated object is readonly through the association.
      # [:validate]
      #   If +false+, don't validate the associated object when saving the parent object. +false+ by default.
      # [:autosave]
      #   If true, always save the associated object or destroy it if marked for destruction,
      #   when saving the parent object. If false, never save or destroy the associated object.
      #   By default, only save the associated object if it's a new record.
      # [:inverse_of]
      #   Specifies the name of the <tt>belongs_to</tt> association on the associated object
      #   that is the inverse of this <tt>has_one</tt> association. Does not work in combination
      #   with <tt>:through</tt> or <tt>:as</tt> options.
      #   See ActiveRecord::Associations::ClassMethods's overview on Bi-directional associations for more detail.
      #
      # Option examples:
      #   has_one :credit_card, :dependent => :destroy  # destroys the associated credit card
      #   has_one :credit_card, :dependent => :nullify  # updates the associated records foreign
      #                                                 # key value to NULL rather than destroying it
      #   has_one :last_comment, :class_name => "Comment", :order => "posted_on"
      #   has_one :project_manager, :class_name => "Person", :conditions => "role = 'project_manager'"
      #   has_one :attachment, :as => :attachable
      #   has_one :boss, :readonly => :true
      #   has_one :club, :through => :membership
      #   has_one :primary_address, :through => :addressables, :conditions => ["addressable.primary = ?", true], :source => :addressable
      def has_one(name, options = {})
        Builder::HasOne.build(self, name, options)
      end

      # Specifies a one-to-one association with another class. This method should only be used
      # if this class contains the foreign key. If the other class contains the foreign key,
      # then you should use +has_one+ instead. See also ActiveRecord::Associations::ClassMethods's overview
      # on when to use +has_one+ and when to use +belongs_to+.
      #
      # Methods will be added for retrieval and query for a single associated object, for which
      # this object holds an id:
      #
      # [association(force_reload = false)]
      #   Returns the associated object. +nil+ is returned if none is found.
      # [association=(associate)]
      #   Assigns the associate object, extracts the primary key, and sets it as the foreign key.
      # [build_association(attributes = {})]
      #   Returns a new object of the associated type that has been instantiated
      #   with +attributes+ and linked to this object through a foreign key, but has not yet been saved.
      # [create_association(attributes = {})]
      #   Returns a new object of the associated type that has been instantiated
      #   with +attributes+, linked to this object through a foreign key, and that
      #   has already been saved (if it passed the validation).
      # [create_association!(attributes = {})]
      #   Does the same as <tt>create_association</tt>, but raises <tt>ActiveRecord::RecordInvalid</tt>
      #   if the record is invalid.
      #
      # (+association+ is replaced with the symbol passed as the first argument, so
      # <tt>belongs_to :author</tt> would add among others <tt>author.nil?</tt>.)
      #
      # === Example
      #
      # A Post class declares <tt>belongs_to :author</tt>, which will add:
      # * <tt>Post#author</tt> (similar to <tt>Author.find(author_id)</tt>)
      # * <tt>Post#author=(author)</tt> (similar to <tt>post.author_id = author.id</tt>)
      # * <tt>Post#build_author</tt> (similar to <tt>post.author = Author.new</tt>)
      # * <tt>Post#create_author</tt> (similar to <tt>post.author = Author.new; post.author.save; post.author</tt>)
      # * <tt>Post#create_author!</tt> (similar to <tt>post.author = Author.new; post.author.save!; post.author</tt>)
      # The declaration can also include an options hash to specialize the behavior of the association.
      #
      # === Options
      #
      # [:class_name]
      #   Specify the class name of the association. Use it only if that name can't be inferred
      #   from the association name. So <tt>belongs_to :author</tt> will by default be linked to the Author class, but
      #   if the real class name is Person, you'll have to specify it with this option.
      # [:conditions]
      #   Specify the conditions that the associated object must meet in order to be included as a +WHERE+
      #   SQL fragment, such as <tt>authorized = 1</tt>.
      # [:select]
      #   By default, this is <tt>*</tt> as in <tt>SELECT * FROM</tt>, but can be changed
      #   if, for example, you want to do a join but not include the joined columns. Do not
      #   forget to include the primary and foreign keys, otherwise it will raise an error.
      # [:foreign_key]
      #   Specify the foreign key used for the association. By default this is guessed to be the name
      #   of the association with an "_id" suffix. So a class that defines a <tt>belongs_to :person</tt>
      #   association will use "person_id" as the default <tt>:foreign_key</tt>. Similarly,
      #   <tt>belongs_to :favorite_person, :class_name => "Person"</tt> will use a foreign key
      #   of "favorite_person_id".
      # [:foreign_type]
      #   Specify the column used to store the associated object's type, if this is a polymorphic
      #   association. By default this is guessed to be the name of the association with a "_type"
      #   suffix. So a class that defines a <tt>belongs_to :taggable, :polymorphic => true</tt>
      #   association will use "taggable_type" as the default <tt>:foreign_type</tt>.
      # [:primary_key]
      #   Specify the method that returns the primary key of associated object used for the association.
      #   By default this is id.
      # [:dependent]
      #   If set to <tt>:destroy</tt>, the associated object is destroyed when this object is. If set to
      #   <tt>:delete</tt>, the associated object is deleted *without* calling its destroy method.
      #   This option should not be specified when <tt>belongs_to</tt> is used in conjunction with
      #   a <tt>has_many</tt> relationship on another class because of the potential to leave
      #   orphaned records behind.
      # [:counter_cache]
      #   Caches the number of belonging objects on the associate class through the use of +increment_counter+
      #   and +decrement_counter+. The counter cache is incremented when an object of this
      #   class is created and decremented when it's destroyed. This requires that a column
      #   named <tt>#{table_name}_count</tt> (such as +comments_count+ for a belonging Comment class)
      #   is used on the associate class (such as a Post class). You can also specify a custom counter
      #   cache column by providing a column name instead of a +true+/+false+ value to this
      #   option (e.g., <tt>:counter_cache => :my_custom_counter</tt>.)
      #   Note: Specifying a counter cache will add it to that model's list of readonly attributes
      #   using +attr_readonly+.
      # [:include]
      #   Specify second-order associations that should be eager loaded when this object is loaded.
      # [:polymorphic]
      #   Specify this association is a polymorphic association by passing +true+.
      #   Note: If you've enabled the counter cache, then you may want to add the counter cache attribute
      #   to the +attr_readonly+ list in the associated classes (e.g. <tt>class Post; attr_readonly :comments_count; end</tt>).
      # [:readonly]
      #   If true, the associated object is readonly through the association.
      # [:validate]
      #   If +false+, don't validate the associated objects when saving the parent object. +false+ by default.
      # [:autosave]
      #   If true, always save the associated object or destroy it if marked for destruction, when
      #   saving the parent object.
      #   If false, never save or destroy the associated object.
      #   By default, only save the associated object if it's a new record.
      # [:touch]
      #   If true, the associated object will be touched (the updated_at/on attributes set to now)
      #   when this record is either saved or destroyed. If you specify a symbol, that attribute
      #   will be updated with the current time in addition to the updated_at/on attribute.
      # [:inverse_of]
      #   Specifies the name of the <tt>has_one</tt> or <tt>has_many</tt> association on the associated
      #   object that is the inverse of this <tt>belongs_to</tt> association. Does not work in
      #   combination with the <tt>:polymorphic</tt> options.
      #   See ActiveRecord::Associations::ClassMethods's overview on Bi-directional associations for more detail.
      #
      # Option examples:
      #   belongs_to :firm, :foreign_key => "client_of"
      #   belongs_to :person, :primary_key => "name", :foreign_key => "person_name"
      #   belongs_to :author, :class_name => "Person", :foreign_key => "author_id"
      #   belongs_to :valid_coupon, :class_name => "Coupon", :foreign_key => "coupon_id",
      #              :conditions => 'discounts > #{payments_count}'
      #   belongs_to :attachable, :polymorphic => true
      #   belongs_to :project, :readonly => true
      #   belongs_to :post, :counter_cache => true
      #   belongs_to :company, :touch => true
      #   belongs_to :company, :touch => :employees_last_updated_at
      def belongs_to(name, options = {})
        Builder::BelongsTo.build(self, name, options)
      end

      # Specifies a many-to-many relationship with another class. This associates two classes via an
      # intermediate join table. Unless the join table is explicitly specified as an option, it is
      # guessed using the lexical order of the class names. So a join between Developer and Project
      # will give the default join table name of "developers_projects" because "D" outranks "P".
      # Note that this precedence is calculated using the <tt><</tt> operator for String. This
      # means that if the strings are of different lengths, and the strings are equal when compared
      # up to the shortest length, then the longer string is considered of higher
      # lexical precedence than the shorter one. For example, one would expect the tables "paper_boxes" and "papers"
      # to generate a join table name of "papers_paper_boxes" because of the length of the name "paper_boxes",
      # but it in fact generates a join table name of "paper_boxes_papers". Be aware of this caveat, and use the
      # custom <tt>:join_table</tt> option if you need to.
      #
      # The join table should not have a primary key or a model associated with it. You must manually generate the
      # join table with a migration such as this:
      #
      #   class CreateDevelopersProjectsJoinTable < ActiveRecord::Migration
      #     def change
      #       create_table :developers_projects, :id => false do |t|
      #         t.integer :developer_id
      #         t.integer :project_id
      #       end
      #     end
      #   end
      #
      # It's also a good idea to add indexes to each of those columns to speed up the joins process.
      # However, in MySQL it is advised to add a compound index for both of the columns as MySQL only
      # uses one index per table during the lookup.
      #
      # Adds the following methods for retrieval and query:
      #
      # [collection(force_reload = false)]
      #   Returns an array of all the associated objects.
      #   An empty array is returned if none are found.
      # [collection<<(object, ...)]
      #   Adds one or more objects to the collection by creating associations in the join table
      #   (<tt>collection.push</tt> and <tt>collection.concat</tt> are aliases to this method).
      #   Note that this operation instantly fires update sql without waiting for the save or update call on the
      #   parent object.
      # [collection.delete(object, ...)]
      #   Removes one or more objects from the collection by removing their associations from the join table.
      #   This does not destroy the objects.
      # [collection=objects]
      #   Replaces the collection's content by deleting and adding objects as appropriate.
      # [collection_singular_ids]
      #   Returns an array of the associated objects' ids.
      # [collection_singular_ids=ids]
      #   Replace the collection by the objects identified by the primary keys in +ids+.
      # [collection.clear]
      #   Removes every object from the collection. This does not destroy the objects.
      # [collection.empty?]
      #   Returns +true+ if there are no associated objects.
      # [collection.size]
      #   Returns the number of associated objects.
      # [collection.find(id)]
      #   Finds an associated object responding to the +id+ and that
      #   meets the condition that it has to be associated with this object.
      #   Uses the same rules as ActiveRecord::Base.find.
      # [collection.exists?(...)]
      #   Checks whether an associated object with the given conditions exists.
      #   Uses the same rules as ActiveRecord::Base.exists?.
      # [collection.build(attributes = {})]
      #   Returns a new object of the collection type that has been instantiated
      #   with +attributes+ and linked to this object through the join table, but has not yet been saved.
      # [collection.create(attributes = {})]
      #   Returns a new object of the collection type that has been instantiated
      #   with +attributes+, linked to this object through the join table, and that has already been
      #   saved (if it passed the validation).
      #
      # (+collection+ is replaced with the symbol passed as the first argument, so
      # <tt>has_and_belongs_to_many :categories</tt> would add among others <tt>categories.empty?</tt>.)
      #
      # === Example
      #
      # A Developer class declares <tt>has_and_belongs_to_many :projects</tt>, which will add:
      # * <tt>Developer#projects</tt>
      # * <tt>Developer#projects<<</tt>
      # * <tt>Developer#projects.delete</tt>
      # * <tt>Developer#projects=</tt>
      # * <tt>Developer#project_ids</tt>
      # * <tt>Developer#project_ids=</tt>
      # * <tt>Developer#projects.clear</tt>
      # * <tt>Developer#projects.empty?</tt>
      # * <tt>Developer#projects.size</tt>
      # * <tt>Developer#projects.find(id)</tt>
      # * <tt>Developer#projects.exists?(...)</tt>
      # * <tt>Developer#projects.build</tt> (similar to <tt>Project.new("developer_id" => id)</tt>)
      # * <tt>Developer#projects.create</tt> (similar to <tt>c = Project.new("developer_id" => id); c.save; c</tt>)
      # The declaration may include an options hash to specialize the behavior of the association.
      #
      # === Options
      #
      # [:class_name]
      #   Specify the class name of the association. Use it only if that name can't be inferred
      #   from the association name. So <tt>has_and_belongs_to_many :projects</tt> will by default be linked to the
      #   Project class, but if the real class name is SuperProject, you'll have to specify it with this option.
      # [:join_table]
      #   Specify the name of the join table if the default based on lexical order isn't what you want.
      #   <b>WARNING:</b> If you're overwriting the table name of either class, the +table_name+ method
      #   MUST be declared underneath any +has_and_belongs_to_many+ declaration in order to work.
      # [:foreign_key]
      #   Specify the foreign key used for the association. By default this is guessed to be the name
      #   of this class in lower-case and "_id" suffixed. So a Person class that makes
      #   a +has_and_belongs_to_many+ association to Project will use "person_id" as the
      #   default <tt>:foreign_key</tt>.
      # [:association_foreign_key]
      #   Specify the foreign key used for the association on the receiving side of the association.
      #   By default this is guessed to be the name of the associated class in lower-case and "_id" suffixed.
      #   So if a Person class makes a +has_and_belongs_to_many+ association to Project,
      #   the association will use "project_id" as the default <tt>:association_foreign_key</tt>.
      # [:conditions]
      #   Specify the conditions that the associated object must meet in order to be included as a +WHERE+
      #   SQL fragment, such as <tt>authorized = 1</tt>. Record creations from the association are
      #   scoped if a hash is used.
      #   <tt>has_many :posts, :conditions => {:published => true}</tt> will create published posts with <tt>@blog.posts.create</tt>
      #   or <tt>@blog.posts.build</tt>.
      # [:order]
      #   Specify the order in which the associated objects are returned as an <tt>ORDER BY</tt> SQL fragment,
      #   such as <tt>last_name, first_name DESC</tt>
      # [:uniq]
      #   If true, duplicate associated objects will be ignored by accessors and query methods.
      # [:finder_sql]
      #   Overwrite the default generated SQL statement used to fetch the association with a manual statement
      # [:counter_sql]
      #   Specify a complete SQL statement to fetch the size of the association. If <tt>:finder_sql</tt> is
      #   specified but not <tt>:counter_sql</tt>, <tt>:counter_sql</tt> will be generated by
      #   replacing <tt>SELECT ... FROM</tt> with <tt>SELECT COUNT(*) FROM</tt>.
      # [:delete_sql]
      #   Overwrite the default generated SQL statement used to remove links between the associated
      #   classes with a manual statement.
      # [:insert_sql]
      #   Overwrite the default generated SQL statement used to add links between the associated classes
      #   with a manual statement.
      # [:extend]
      #   Anonymous module for extending the proxy, see "Association extensions".
      # [:include]
      #   Specify second-order associations that should be eager loaded when the collection is loaded.
      # [:group]
      #   An attribute name by which the result should be grouped. Uses the <tt>GROUP BY</tt> SQL-clause.
      # [:having]
      #   Combined with +:group+ this can be used to filter the records that a <tt>GROUP BY</tt> returns.
      #   Uses the <tt>HAVING</tt> SQL-clause.
      # [:limit]
      #   An integer determining the limit on the number of rows that should be returned.
      # [:offset]
      #   An integer determining the offset from where the rows should be fetched. So at 5,
      #   it would skip the first 4 rows.
      # [:select]
      #   By default, this is <tt>*</tt> as in <tt>SELECT * FROM</tt>, but can be changed if, for example,
      #   you want to do a join but not include the joined columns. Do not forget to include the primary
      #   and foreign keys, otherwise it will raise an error.
      # [:readonly]
      #   If true, all the associated objects are readonly through the association.
      # [:validate]
      #   If +false+, don't validate the associated objects when saving the parent object. +true+ by default.
      # [:autosave]
      #   If true, always save the associated objects or destroy them if marked for destruction, when
      #   saving the parent object.
      #   If false, never save or destroy the associated objects.
      #   By default, only save associated objects that are new records.
      #
      # Option examples:
      #   has_and_belongs_to_many :projects
      #   has_and_belongs_to_many :projects, :include => [ :milestones, :manager ]
      #   has_and_belongs_to_many :nations, :class_name => "Country"
      #   has_and_belongs_to_many :categories, :join_table => "prods_cats"
      #   has_and_belongs_to_many :categories, :readonly => true
      #   has_and_belongs_to_many :active_projects, :join_table => 'developers_projects', :delete_sql =>
      #   "DELETE FROM developers_projects WHERE active=1 AND developer_id = #{id} AND project_id = #{record.id}"
      def has_and_belongs_to_many(name, options = {}, &extension)
        Builder::HasAndBelongsToMany.build(self, name, options, &extension)
      end
    end
  end
end
require 'active_support/concern'

module ActiveRecord
  module AttributeAssignment
    extend ActiveSupport::Concern
    include ActiveModel::MassAssignmentSecurity

    module ClassMethods
      private

      # The primary key and inheritance column can never be set by mass-assignment for security reasons.
      def attributes_protected_by_default
        default = [ primary_key, inheritance_column ]
        default << 'id' unless primary_key.eql? 'id'
        default
      end
    end

    # Allows you to set all the attributes at once by passing in a hash with keys
    # matching the attribute names (which again matches the column names).
    #
    # If any attributes are protected by either +attr_protected+ or
    # +attr_accessible+ then only settable attributes will be assigned.
    #
    #   class User < ActiveRecord::Base
    #     attr_protected :is_admin
    #   end
    #
    #   user = User.new
    #   user.attributes = { :username => 'Phusion', :is_admin => true }
    #   user.username   # => "Phusion"
    #   user.is_admin?  # => false
    def attributes=(new_attributes)
      return unless new_attributes.is_a?(Hash)

      assign_attributes(new_attributes)
    end

    # Allows you to set all the attributes for a particular mass-assignment
    # security role by passing in a hash of attributes with keys matching
    # the attribute names (which again matches the column names) and the role
    # name using the :as option.
    #
    # To bypass mass-assignment security you can use the :without_protection => true
    # option.
    #
    #   class User < ActiveRecord::Base
    #     attr_accessible :name
    #     attr_accessible :name, :is_admin, :as => :admin
    #   end
    #
    #   user = User.new
    #   user.assign_attributes({ :name => 'Josh', :is_admin => true })
    #   user.name       # => "Josh"
    #   user.is_admin?  # => false
    #
    #   user = User.new
    #   user.assign_attributes({ :name => 'Josh', :is_admin => true }, :as => :admin)
    #   user.name       # => "Josh"
    #   user.is_admin?  # => true
    #
    #   user = User.new
    #   user.assign_attributes({ :name => 'Josh', :is_admin => true }, :without_protection => true)
    #   user.name       # => "Josh"
    #   user.is_admin?  # => true
    def assign_attributes(new_attributes, options = {})
      return if new_attributes.blank?

      attributes = new_attributes.stringify_keys
      multi_parameter_attributes = []
      nested_parameter_attributes = []
      @mass_assignment_options = options

      unless options[:without_protection]
        attributes = sanitize_for_mass_assignment(attributes, mass_assignment_role)
      end

      attributes.each do |k, v|
        if k.include?("(")
          multi_parameter_attributes << [ k, v ]
        elsif respond_to?("#{k}=")
          if v.is_a?(Hash)
            nested_parameter_attributes << [ k, v ]
          else
            send("#{k}=", v)
          end
        else
          raise(UnknownAttributeError, "unknown attribute: #{k}")
        end
      end

      # assign any deferred nested attributes after the base attributes have been set
      nested_parameter_attributes.each do |k,v|
        send("#{k}=", v)
      end

      @mass_assignment_options = nil
      assign_multiparameter_attributes(multi_parameter_attributes)
    end

    protected

    def mass_assignment_options
      @mass_assignment_options ||= {}
    end

    def mass_assignment_role
      mass_assignment_options[:as] || :default
    end

    private

    # Instantiates objects for all attribute classes that needs more than one constructor parameter. This is done
    # by calling new on the column type or aggregation type (through composed_of) object with these parameters.
    # So having the pairs written_on(1) = "2004", written_on(2) = "6", written_on(3) = "24", will instantiate
    # written_on (a date type) with Date.new("2004", "6", "24"). You can also specify a typecast character in the
    # parentheses to have the parameters typecasted before they're used in the constructor. Use i for Fixnum,
    # f for Float, s for String, and a for Array. If all the values for a given attribute are empty, the
    # attribute will be set to nil.
    def assign_multiparameter_attributes(pairs)
      execute_callstack_for_multiparameter_attributes(
        extract_callstack_for_multiparameter_attributes(pairs)
      )
    end

    def instantiate_time_object(name, values)
      if self.class.send(:create_time_zone_conversion_attribute?, name, column_for_attribute(name))
        Time.zone.local(*values)
      else
        Time.time_with_datetime_fallback(self.class.default_timezone, *values)
      end
    end

    def execute_callstack_for_multiparameter_attributes(callstack)
      errors = []
      callstack.each do |name, values_with_empty_parameters|
        begin
          send(name + "=", read_value_from_parameter(name, values_with_empty_parameters))
        rescue => ex
          errors << AttributeAssignmentError.new("error on assignment #{values_with_empty_parameters.values.inspect} to #{name}", ex, name)
        end
      end
      unless errors.empty?
        raise MultiparameterAssignmentErrors.new(errors), "#{errors.size} error(s) on assignment of multiparameter attributes"
      end
    end

    def read_value_from_parameter(name, values_hash_from_param)
      klass = (self.class.reflect_on_aggregation(name.to_sym) || column_for_attribute(name)).klass
      if values_hash_from_param.values.all?{|v|v.nil?}
        nil
      elsif klass == Time
        read_time_parameter_value(name, values_hash_from_param)
      elsif klass == Date
        read_date_parameter_value(name, values_hash_from_param)
      else
        read_other_parameter_value(klass, name, values_hash_from_param)
      end
    end

    def read_time_parameter_value(name, values_hash_from_param)
      # If Date bits were not provided, error
      raise "Missing Parameter" if [1,2,3].any?{|position| !values_hash_from_param.has_key?(position)}
      max_position = extract_max_param_for_multiparameter_attributes(values_hash_from_param, 6)
      # If Date bits were provided but blank, then return nil
      return nil if (1..3).any? {|position| values_hash_from_param[position].blank?}

      set_values = (1..max_position).collect{|position| values_hash_from_param[position] }
      # If Time bits are not there, then default to 0
      (3..5).each {|i| set_values[i] = set_values[i].blank? ? 0 : set_values[i]}
      instantiate_time_object(name, set_values)
    end

    def read_date_parameter_value(name, values_hash_from_param)
      return nil if (1..3).any? {|position| values_hash_from_param[position].blank?}
      set_values = [values_hash_from_param[1], values_hash_from_param[2], values_hash_from_param[3]]
      begin
        Date.new(*set_values)
      rescue ArgumentError # if Date.new raises an exception on an invalid date
        instantiate_time_object(name, set_values).to_date # we instantiate Time object and convert it back to a date thus using Time's logic in handling invalid dates
      end
    end

    def read_other_parameter_value(klass, name, values_hash_from_param)
      max_position = extract_max_param_for_multiparameter_attributes(values_hash_from_param)
      values = (1..max_position).collect do |position|
        raise "Missing Parameter" if !values_hash_from_param.has_key?(position)
        values_hash_from_param[position]
      end
      klass.new(*values)
    end

    def extract_max_param_for_multiparameter_attributes(values_hash_from_param, upper_cap = 100)
      [values_hash_from_param.keys.max,upper_cap].min
    end

    def extract_callstack_for_multiparameter_attributes(pairs)
      attributes = { }

      pairs.each do |pair|
        multiparameter_name, value = pair
        attribute_name = multiparameter_name.split("(").first
        attributes[attribute_name] = {} unless attributes.include?(attribute_name)

        parameter_value = value.empty? ? nil : type_cast_attribute_value(multiparameter_name, value)
        attributes[attribute_name][find_parameter_position(multiparameter_name)] ||= parameter_value
      end

      attributes
    end

    def type_cast_attribute_value(multiparameter_name, value)
      multiparameter_name =~ /\([0-9]*([if])\)/ ? value.send("to_" + $1) : value
    end

    def find_parameter_position(multiparameter_name)
      multiparameter_name.scan(/\(([0-9]*).*\)/).first.first.to_i
    end

  end
end
module ActiveRecord
  module AttributeMethods
    module BeforeTypeCast
      extend ActiveSupport::Concern

      included do
        attribute_method_suffix "_before_type_cast"
      end

      def read_attribute_before_type_cast(attr_name)
        @attributes[attr_name]
      end

      # Returns a hash of attributes before typecasting and deserialization.
      def attributes_before_type_cast
        @attributes
      end

      private

      # Handle *_before_type_cast for method_missing.
      def attribute_before_type_cast(attribute_name)
        if attribute_name == 'id'
          read_attribute_before_type_cast(self.class.primary_key)
        else
          read_attribute_before_type_cast(attribute_name)
        end
      end
    end
  end
end
require 'active_support/concern'
require 'active_support/deprecation'

module ActiveRecord
  module AttributeMethods
    module DeprecatedUnderscoreRead
      extend ActiveSupport::Concern

      included do
        attribute_method_prefix "_"
      end

      module ClassMethods
        protected

        def define_method__attribute(attr_name)
          # Do nothing, let it hit method missing instead.
        end
      end

      protected

      def _attribute(attr_name)
        ActiveSupport::Deprecation.warn(
          "You have called '_#{attr_name}'. This is deprecated. Please use " \
          "either '#{attr_name}' or read_attribute('#{attr_name}')."
        )
        read_attribute(attr_name)
      end
    end
  end
end
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/object/blank'

module ActiveRecord
  module AttributeMethods
    module Dirty
      extend ActiveSupport::Concern
      include ActiveModel::Dirty
      include AttributeMethods::Write

      included do
        if self < ::ActiveRecord::Timestamp
          raise "You cannot include Dirty after Timestamp"
        end

        class_attribute :partial_updates
        self.partial_updates = true
      end

      # Attempts to +save+ the record and clears changed attributes if successful.
      def save(*) #:nodoc:
        if status = super
          @previously_changed = changes
          @changed_attributes.clear
        elsif IdentityMap.enabled?
          IdentityMap.remove(self)
        end
        status
      end

      # Attempts to <tt>save!</tt> the record and clears changed attributes if successful.
      def save!(*) #:nodoc:
        super.tap do
          @previously_changed = changes
          @changed_attributes.clear
        end
      rescue
        IdentityMap.remove(self) if IdentityMap.enabled?
        raise
      end

      # <tt>reload</tt> the record and clears changed attributes.
      def reload(*) #:nodoc:
        super.tap do
          @previously_changed.clear
          @changed_attributes.clear
        end
      end

    private
      # Wrap write_attribute to remember original attribute value.
      def write_attribute(attr, value)
        attr = attr.to_s

        # The attribute already has an unsaved change.
        if attribute_changed?(attr)
          old = @changed_attributes[attr]
          @changed_attributes.delete(attr) unless _field_changed?(attr, old, value)
        else
          old = clone_attribute_value(:read_attribute, attr)
          # Save Time objects as TimeWithZone if time_zone_aware_attributes == true
          old = old.in_time_zone if clone_with_time_zone_conversion_attribute?(attr, old)
          @changed_attributes[attr] = old if _field_changed?(attr, old, value)
        end

        # Carry on.
        super(attr, value)
      end

      def update(*)
        if partial_updates?
          # Serialized attributes should always be written in case they've been
          # changed in place.
          super(changed | (attributes.keys & self.class.serialized_attributes.keys))
        else
          super
        end
      end

      def _field_changed?(attr, old, value)
        if column = column_for_attribute(attr)
          if column.number? && (changes_from_nil_to_empty_string?(column, old, value) ||
                                changes_from_zero_to_string?(old, value))
            value = nil
          else
            value = column.type_cast(value)
          end
        end

        old != value
      end

      def clone_with_time_zone_conversion_attribute?(attr, old)
        old.class.name == "Time" && time_zone_aware_attributes && !self.skip_time_zone_conversion_for_attributes.include?(attr.to_sym)
      end

      def changes_from_nil_to_empty_string?(column, old, value)
        # For nullable numeric columns, NULL gets stored in database for blank (i.e. '') values.
        # Hence we don't record it as a change if the value changes from nil to ''.
        # If an old value of 0 is set to '' we want this to get changed to nil as otherwise it'll
        # be typecast back to 0 (''.to_i => 0)
        column.null && (old.nil? || old == 0) && value.blank?
      end

      def changes_from_zero_to_string?(old, value)
        # For columns with old 0 and value non-empty string
        old == 0 && value.is_a?(String) && value.present? && value != '0'
      end
    end
  end
end
module ActiveRecord
  module AttributeMethods
    module PrimaryKey
      extend ActiveSupport::Concern

      # Returns this record's primary key value wrapped in an Array if one is available
      def to_key
        key = self.id
        [key] if key
      end

      # Returns the primary key value
      def id
        read_attribute(self.class.primary_key)
      end

      # Sets the primary key value
      def id=(value)
        write_attribute(self.class.primary_key, value)
      end

      # Queries the primary key value
      def id?
        query_attribute(self.class.primary_key)
      end

      module ClassMethods
        def define_method_attribute(attr_name)
          super

          if attr_name == primary_key && attr_name != 'id'
            generated_attribute_methods.send(:alias_method, :id, primary_key)
            generated_external_attribute_methods.module_eval <<-CODE, __FILE__, __LINE__
              def id(v, attributes, attributes_cache, attr_name)
                attr_name = '#{primary_key}'
                send(attr_name, attributes[attr_name], attributes, attributes_cache, attr_name)
              end
            CODE
          end
        end

        def dangerous_attribute_method?(method_name)
          super && !['id', 'id=', 'id?'].include?(method_name)
        end

        # Defines the primary key field -- can be overridden in subclasses. Overwriting will negate any effect of the
        # primary_key_prefix_type setting, though.
        def primary_key
          @primary_key = reset_primary_key unless defined? @primary_key
          @primary_key
        end

        # Returns a quoted version of the primary key name, used to construct SQL statements.
        def quoted_primary_key
          @quoted_primary_key ||= connection.quote_column_name(primary_key)
        end

        def reset_primary_key #:nodoc:
          if self == base_class
            self.primary_key = get_primary_key(base_class.name)
          else
            self.primary_key = base_class.primary_key
          end
        end

        def get_primary_key(base_name) #:nodoc:
          return 'id' unless base_name && !base_name.blank?

          case primary_key_prefix_type
          when :table_name
            base_name.foreign_key(false)
          when :table_name_with_underscore
            base_name.foreign_key
          else
            if ActiveRecord::Base != self && table_exists?
              connection.schema_cache.primary_keys[table_name]
            else
              'id'
            end
          end
        end

        def original_primary_key #:nodoc:
          deprecated_original_property_getter :primary_key
        end

        # Sets the name of the primary key column.
        #
        #   class Project < ActiveRecord::Base
        #     self.primary_key = "sysid"
        #   end
        #
        # You can also define the primary_key method yourself:
        #
        #   class Project < ActiveRecord::Base
        #     def self.primary_key
        #       "foo_" + super
        #     end
        #   end
        #   Project.primary_key # => "foo_id"
        def primary_key=(value)
          @original_primary_key = @primary_key if defined?(@primary_key)
          @primary_key          = value && value.to_s
          @quoted_primary_key   = nil
        end

        def set_primary_key(value = nil, &block) #:nodoc:
          deprecated_property_setter :primary_key, value, block
          @quoted_primary_key = nil
        end
      end
    end
  end
end
require 'active_support/core_ext/object/blank'

module ActiveRecord
  module AttributeMethods
    module Query
      extend ActiveSupport::Concern

      included do
        attribute_method_suffix "?"
      end

      def query_attribute(attr_name)
        unless value = read_attribute(attr_name)
          false
        else
          column = self.class.columns_hash[attr_name]
          if column.nil?
            if Numeric === value || value !~ /[^0-9]/
              !value.to_i.zero?
            else
              return false if ActiveRecord::ConnectionAdapters::Column::FALSE_VALUES.include?(value)
              !value.blank?
            end
          elsif column.number?
            !value.zero?
          else
            !value.blank?
          end
        end
      end

      private
        # Handle *? for method_missing.
        def attribute?(attribute_name)
          query_attribute(attribute_name)
        end
    end
  end
end
module ActiveRecord
  module AttributeMethods
    module Read
      extend ActiveSupport::Concern

      ATTRIBUTE_TYPES_CACHED_BY_DEFAULT = [:datetime, :timestamp, :time, :date]

      included do
        cattr_accessor :attribute_types_cached_by_default, :instance_writer => false
        self.attribute_types_cached_by_default = ATTRIBUTE_TYPES_CACHED_BY_DEFAULT
      end

      module ClassMethods
        # +cache_attributes+ allows you to declare which converted attribute values should
        # be cached. Usually caching only pays off for attributes with expensive conversion
        # methods, like time related columns (e.g. +created_at+, +updated_at+).
        def cache_attributes(*attribute_names)
          cached_attributes.merge attribute_names.map { |attr| attr.to_s }
        end

        # Returns the attributes which are cached. By default time related columns
        # with datatype <tt>:datetime, :timestamp, :time, :date</tt> are cached.
        def cached_attributes
          @cached_attributes ||= columns.select { |c| cacheable_column?(c) }.map { |col| col.name }.to_set
        end

        # Returns +true+ if the provided attribute is being cached.
        def cache_attribute?(attr_name)
          cached_attributes.include?(attr_name)
        end

        def undefine_attribute_methods
          generated_external_attribute_methods.module_eval do
            instance_methods.each { |m| undef_method(m) }
          end

          super
        end

        def type_cast_attribute(attr_name, attributes, cache = {}) #:nodoc:
          return unless attr_name
          attr_name = attr_name.to_s

          if generated_external_attribute_methods.method_defined?(attr_name)
            if attributes.has_key?(attr_name) || attr_name == 'id'
              generated_external_attribute_methods.send(attr_name, attributes[attr_name], attributes, cache, attr_name)
            end
          elsif !attribute_methods_generated?
            # If we haven't generated the caster methods yet, do that and
            # then try again
            define_attribute_methods
            type_cast_attribute(attr_name, attributes, cache)
          else
            # If we get here, the attribute has no associated DB column, so
            # just return it verbatim.
            attributes[attr_name]
          end
        end

        protected
          # We want to generate the methods via module_eval rather than define_method,
          # because define_method is slower on dispatch and uses more memory (because it
          # creates a closure).
          #
          # But sometimes the database might return columns with characters that are not
          # allowed in normal method names (like 'my_column(omg)'. So to work around this
          # we first define with the __temp__ identifier, and then use alias method to
          # rename it to what we want.
          def define_method_attribute(attr_name)
            generated_attribute_methods.module_eval <<-STR, __FILE__, __LINE__ + 1
              def __temp__
                #{internal_attribute_access_code(attr_name, attribute_cast_code(attr_name))}
              end
              alias_method '#{attr_name}', :__temp__
              undef_method :__temp__
            STR
          end

        private

          def define_external_attribute_method(attr_name)
            generated_external_attribute_methods.module_eval <<-STR, __FILE__, __LINE__ + 1
              def __temp__(v, attributes, attributes_cache, attr_name)
                #{external_attribute_access_code(attr_name, attribute_cast_code(attr_name))}
              end
              alias_method '#{attr_name}', :__temp__
              undef_method :__temp__
            STR
          end

          def cacheable_column?(column)
            attribute_types_cached_by_default.include?(column.type)
          end

          def internal_attribute_access_code(attr_name, cast_code)
            access_code = "(v=@attributes[attr_name]) && #{cast_code}"

            unless attr_name == primary_key
              access_code.insert(0, "missing_attribute(attr_name, caller) unless @attributes.has_key?(attr_name); ")
            end

            if cache_attribute?(attr_name)
              access_code = "@attributes_cache[attr_name] ||= (#{access_code})"
            end

            "attr_name = '#{attr_name}'; #{access_code}"
          end

          def external_attribute_access_code(attr_name, cast_code)
            access_code = "v && #{cast_code}"

            if cache_attribute?(attr_name)
              access_code = "attributes_cache[attr_name] ||= (#{access_code})"
            end

            access_code
          end

          def attribute_cast_code(attr_name)
            columns_hash[attr_name].type_cast_code('v')
          end
      end

      # Returns the value of the attribute identified by <tt>attr_name</tt> after it has been typecast (for example,
      # "2004-12-12" in a data column is cast to a date object, like Date.new(2004, 12, 12)).
      def read_attribute(attr_name)
        self.class.type_cast_attribute(attr_name, @attributes, @attributes_cache)
      end

      private
        def attribute(attribute_name)
          read_attribute(attribute_name)
        end
    end
  end
end
module ActiveRecord
  module AttributeMethods
    module Serialization
      extend ActiveSupport::Concern

      included do
        # Returns a hash of all the attributes that have been specified for serialization as
        # keys and their class restriction as values.
        class_attribute :serialized_attributes
        self.serialized_attributes = {}
      end

      class Attribute < Struct.new(:coder, :value, :state)
        def unserialized_value
          state == :serialized ? unserialize : value
        end

        def serialized_value
          state == :unserialized ? serialize : value
        end

        def unserialize
          self.state = :unserialized
          self.value = coder.load(value)
        end

        def serialize
          self.state = :serialized
          self.value = coder.dump(value)
        end
      end

      module ClassMethods
        # If you have an attribute that needs to be saved to the database as an object, and retrieved as the same object,
        # then specify the name of that attribute using this method and it will be handled automatically.
        # The serialization is done through YAML. If +class_name+ is specified, the serialized object must be of that
        # class on retrieval or SerializationTypeMismatch will be raised.
        #
        # ==== Parameters
        #
        # * +attr_name+ - The field name that should be serialized.
        # * +class_name+ - Optional, class name that the object type should be equal to.
        #
        # ==== Example
        #   # Serialize a preferences attribute
        #   class User < ActiveRecord::Base
        #     serialize :preferences
        #   end
        def serialize(attr_name, class_name = Object)
          coder = if [:load, :dump].all? { |x| class_name.respond_to?(x) }
                    class_name
                  else
                    Coders::YAMLColumn.new(class_name)
                  end

          # merge new serialized attribute and create new hash to ensure that each class in inheritance hierarchy
          # has its own hash of own serialized attributes
          self.serialized_attributes = serialized_attributes.merge(attr_name.to_s => coder)
        end

        def initialize_attributes(attributes, options = {}) #:nodoc:
          serialized = (options.delete(:serialized) { true }) ? :serialized : :unserialized
          super(attributes, options)

          serialized_attributes.each do |key, coder|
            if attributes.key?(key)
              attributes[key] = Attribute.new(coder, attributes[key], serialized)
            end
          end

          attributes
        end

        private

        def attribute_cast_code(attr_name)
          if serialized_attributes.include?(attr_name)
            "v.unserialized_value"
          else
            super
          end
        end
      end

      def type_cast_attribute_for_write(column, value)
        if column && coder = self.class.serialized_attributes[column.name]
          Attribute.new(coder, value, :unserialized)
        else
          super
        end
      end

      def read_attribute_before_type_cast(attr_name)
        if serialized_attributes.include?(attr_name)
          super.unserialized_value
        else
          super
        end
      end
    end
  end
end
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/object/inclusion'

module ActiveRecord
  module AttributeMethods
    module TimeZoneConversion
      extend ActiveSupport::Concern

      included do
        cattr_accessor :time_zone_aware_attributes, :instance_writer => false
        self.time_zone_aware_attributes = false

        class_attribute :skip_time_zone_conversion_for_attributes, :instance_writer => false
        self.skip_time_zone_conversion_for_attributes = []
      end

      module ClassMethods
        protected
          # The enhanced read method automatically converts the UTC time stored in the database to the time
          # zone stored in Time.zone.
          def attribute_cast_code(attr_name)
            column = columns_hash[attr_name]

            if create_time_zone_conversion_attribute?(attr_name, column)
              typecast             = "v = #{super}"
              time_zone_conversion = "v.acts_like?(:time) ? v.in_time_zone : v"

              "((#{typecast}) && (#{time_zone_conversion}))"
            else
              super
            end
          end

          # Defined for all +datetime+ and +timestamp+ attributes when +time_zone_aware_attributes+ are enabled.
          # This enhanced write method will automatically convert the time passed to it to the zone stored in Time.zone.
          def define_method_attribute=(attr_name)
            if create_time_zone_conversion_attribute?(attr_name, columns_hash[attr_name])
              method_body, line = <<-EOV, __LINE__ + 1
                def #{attr_name}=(original_time)
                  time = original_time
                  unless time.acts_like?(:time)
                    time = time.is_a?(String) ? Time.zone.parse(time) : time.to_time rescue time
                  end
                  zoned_time   = time && time.in_time_zone rescue nil
                  rounded_time = round_usec(zoned_time)
                  rounded_value = round_usec(read_attribute("#{attr_name}"))
                  if (rounded_value != rounded_time) || (!rounded_value && original_time)
                    write_attribute("#{attr_name}", original_time)
                    #{attr_name}_will_change!
                    @attributes_cache["#{attr_name}"] = zoned_time
                  end
                end
              EOV
              generated_attribute_methods.module_eval(method_body, __FILE__, line)
            else
              super
            end
          end

        private
          def create_time_zone_conversion_attribute?(name, column)
            time_zone_aware_attributes && !self.skip_time_zone_conversion_for_attributes.include?(name.to_sym) && column.type.in?([:datetime, :timestamp])
          end
      end

      private
      def round_usec(value)
        return unless value
        value.change(:usec => 0)
      end
    end
  end
end
module ActiveRecord
  module AttributeMethods
    module Write
      extend ActiveSupport::Concern

      included do
        attribute_method_suffix "="
      end

      module ClassMethods
        protected
          def define_method_attribute=(attr_name)
            if attr_name =~ ActiveModel::AttributeMethods::NAME_COMPILABLE_REGEXP
              generated_attribute_methods.module_eval("def #{attr_name}=(new_value); write_attribute('#{attr_name}', new_value); end", __FILE__, __LINE__)
            else
              generated_attribute_methods.send(:define_method, "#{attr_name}=") do |new_value|
                write_attribute(attr_name, new_value)
              end
            end
          end
      end

      # Updates the attribute identified by <tt>attr_name</tt> with the specified +value+. Empty strings
      # for fixnum and float columns are turned into +nil+.
      def write_attribute(attr_name, value)
        attr_name = attr_name.to_s
        attr_name = self.class.primary_key if attr_name == 'id' && self.class.primary_key
        @attributes_cache.delete(attr_name)
        column = column_for_attribute(attr_name)

        unless column || @attributes.has_key?(attr_name)
          ActiveSupport::Deprecation.warn(
            "You're trying to create an attribute `#{attr_name}'. Writing arbitrary " \
            "attributes on a model is deprecated. Please just use `attr_writer` etc."
          )
        end

        @attributes[attr_name] = type_cast_attribute_for_write(column, value)
      end
      alias_method :raw_write_attribute, :write_attribute

      private
        # Handle *= for method_missing.
        def attribute=(attribute_name, value)
          write_attribute(attribute_name, value)
        end

        def type_cast_attribute_for_write(column, value)
          if column && column.number?
            convert_number_column_value(value)
          else
            value
          end
        end

        def convert_number_column_value(value)
          if value == false
            0
          elsif value == true
            1
          elsif value.is_a?(String) && value.blank?
            nil
          else
            value
          end
        end
    end
  end
end
require 'active_support/core_ext/enumerable'
require 'active_support/deprecation'

module ActiveRecord
  # = Active Record Attribute Methods
  module AttributeMethods #:nodoc:
    extend ActiveSupport::Concern
    include ActiveModel::AttributeMethods

    included do
      include Read
      include Write
      include BeforeTypeCast
      include Query
      include PrimaryKey
      include TimeZoneConversion
      include Dirty
      include Serialization
      include DeprecatedUnderscoreRead

      # Returns the value of the attribute identified by <tt>attr_name</tt> after it has been typecast (for example,
      # "2004-12-12" in a data column is cast to a date object, like Date.new(2004, 12, 12)).
      # (Alias for the protected read_attribute method).
      def [](attr_name)
        read_attribute(attr_name)
      end

      # Updates the attribute identified by <tt>attr_name</tt> with the specified +value+.
      # (Alias for the protected write_attribute method).
      def []=(attr_name, value)
        write_attribute(attr_name, value)
      end
    end

    module ClassMethods
      # Generates all the attribute related methods for columns in the database
      # accessors, mutators and query methods.
      def define_attribute_methods
        unless defined?(@attribute_methods_mutex)
          msg = "It looks like something (probably a gem/plugin) is overriding the " \
                "ActiveRecord::Base.inherited method. It is important that this hook executes so " \
                "that your models are set up correctly. A workaround has been added to stop this " \
                "causing an error in 3.2, but future versions will simply not work if the hook is " \
                "overridden. If you are using Kaminari, please upgrade as it is known to have had " \
                "this problem.\n\n"
          msg << "The following may help track down the problem:"

          meth = method(:inherited)
          if meth.respond_to?(:source_location)
            msg << " #{meth.source_location.inspect}"
          else
            msg << " #{meth.inspect}"
          end
          msg << "\n\n"

          ActiveSupport::Deprecation.warn(msg)

          @attribute_methods_mutex = Mutex.new
        end

        # Use a mutex; we don't want two thread simaltaneously trying to define
        # attribute methods.
        @attribute_methods_mutex.synchronize do
          return if attribute_methods_generated?
          superclass.define_attribute_methods unless self == base_class
          super(column_names)
          column_names.each { |name| define_external_attribute_method(name) }
          @attribute_methods_generated = true
        end
      end

      def attribute_methods_generated?
        @attribute_methods_generated ||= false
      end

      # We will define the methods as instance methods, but will call them as singleton
      # methods. This allows us to use method_defined? to check if the method exists,
      # which is fast and won't give any false positives from the ancestors (because
      # there are no ancestors).
      def generated_external_attribute_methods
        @generated_external_attribute_methods ||= Module.new { extend self }
      end

      def undefine_attribute_methods
        super
        @attribute_methods_generated = false
      end

      def instance_method_already_implemented?(method_name)
        if dangerous_attribute_method?(method_name)
          raise DangerousAttributeError, "#{method_name} is defined by ActiveRecord"
        end

        if superclass == Base
          super
        else
          # If B < A and A defines its own attribute method, then we don't want to overwrite that.
          defined = method_defined_within?(method_name, superclass, superclass.generated_attribute_methods)
          defined && !ActiveRecord::Base.method_defined?(method_name) || super
        end
      end

      # A method name is 'dangerous' if it is already defined by Active Record, but
      # not by any ancestors. (So 'puts' is not dangerous but 'save' is.)
      def dangerous_attribute_method?(name)
        method_defined_within?(name, Base)
      end

      def method_defined_within?(name, klass, sup = klass.superclass)
        if klass.method_defined?(name) || klass.private_method_defined?(name)
          if sup.method_defined?(name) || sup.private_method_defined?(name)
            klass.instance_method(name).owner != sup.instance_method(name).owner
          else
            true
          end
        else
          false
        end
      end

      def attribute_method?(attribute)
        super || (table_exists? && column_names.include?(attribute.to_s.sub(/=$/, '')))
      end

      # Returns an array of column names as strings if it's not
      # an abstract class and table exists.
      # Otherwise it returns an empty array.
      def attribute_names
        @attribute_names ||= if !abstract_class? && table_exists?
            column_names
          else
            []
          end
      end
    end

    # If we haven't generated any methods yet, generate them, then
    # see if we've created the method we're looking for.
    def method_missing(method, *args, &block)
      unless self.class.attribute_methods_generated?
        self.class.define_attribute_methods

        if respond_to_without_attributes?(method)
          send(method, *args, &block)
        else
          super
        end
      else
        super
      end
    end

    def attribute_missing(match, *args, &block)
      if self.class.columns_hash[match.attr_name]
        ActiveSupport::Deprecation.warn(
          "The method `#{match.method_name}', matching the attribute `#{match.attr_name}' has " \
          "dispatched through method_missing. This shouldn't happen, because `#{match.attr_name}' " \
          "is a column of the table. If this error has happened through normal usage of Active " \
          "Record (rather than through your own code or external libraries), please report it as " \
          "a bug."
        )
      end

      super
    end

    def respond_to?(name, include_private = false)
      self.class.define_attribute_methods unless self.class.attribute_methods_generated?
      super
    end

    # Returns true if the given attribute is in the attributes hash
    def has_attribute?(attr_name)
      @attributes.has_key?(attr_name.to_s)
    end

    # Returns an array of names for the attributes available on this object.
    def attribute_names
      @attributes.keys
    end

    # Returns a hash of all the attributes with their names as keys and the values of the attributes as values.
    def attributes
      attrs = {}
      attribute_names.each { |name| attrs[name] = read_attribute(name) }
      attrs
    end

    # Returns an <tt>#inspect</tt>-like string for the value of the
    # attribute +attr_name+. String attributes are truncated upto 50
    # characters, and Date and Time attributes are returned in the
    # <tt>:db</tt> format. Other attributes return the value of
    # <tt>#inspect</tt> without modification.
    #
    #   person = Person.create!(:name => "David Heinemeier Hansson " * 3)
    #
    #   person.attribute_for_inspect(:name)
    #   # => '"David Heinemeier Hansson David Heinemeier Hansson D..."'
    #
    #   person.attribute_for_inspect(:created_at)
    #   # => '"2009-01-12 04:48:57"'
    def attribute_for_inspect(attr_name)
      value = read_attribute(attr_name)

      if value.is_a?(String) && value.length > 50
        "#{value[0..50]}...".inspect
      elsif value.is_a?(Date) || value.is_a?(Time)
        %("#{value.to_s(:db)}")
      else
        value.inspect
      end
    end

    # Returns true if the specified +attribute+ has been set by the user or by a database load and is neither
    # nil nor empty? (the latter only applies to objects that respond to empty?, most notably Strings).
    def attribute_present?(attribute)
      value = read_attribute(attribute)
      !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
    end

    # Returns the column object for the named attribute.
    def column_for_attribute(name)
      self.class.columns_hash[name.to_s]
    end

    protected

    def clone_attributes(reader_method = :read_attribute, attributes = {})
      attribute_names.each do |name|
        attributes[name] = clone_attribute_value(reader_method, name)
      end
      attributes
    end

    def clone_attribute_value(reader_method, attribute_name)
      value = send(reader_method, attribute_name)
      value.duplicable? ? value.clone : value
    rescue TypeError, NoMethodError
      value
    end

    # Returns a copy of the attributes hash where all the values have been safely quoted for use in
    # an Arel insert/update method.
    def arel_attributes_values(include_primary_key = true, include_readonly_attributes = true, attribute_names = @attributes.keys)
      attrs      = {}
      klass      = self.class
      arel_table = klass.arel_table

      attribute_names.each do |name|
        if (column = column_for_attribute(name)) && (include_primary_key || !column.primary)

          if include_readonly_attributes || !self.class.readonly_attributes.include?(name)

            value = if klass.serialized_attributes.include?(name)
                      @attributes[name].serialized_value
                    else
                      # FIXME: we need @attributes to be used consistently.
                      # If the values stored in @attributes were already type
                      # casted, this code could be simplified
                      read_attribute(name)
                    end

            attrs[arel_table[name]] = value
          end
        end
      end

      attrs
    end

    def attribute_method?(attr_name)
      attr_name == 'id' || (defined?(@attributes) && @attributes.include?(attr_name))
    end
  end
end
require 'active_support/core_ext/array/wrap'

module ActiveRecord
  # = Active Record Autosave Association
  #
  # +AutosaveAssociation+ is a module that takes care of automatically saving
  # associated records when their parent is saved. In addition to saving, it
  # also destroys any associated records that were marked for destruction.
  # (See +mark_for_destruction+ and <tt>marked_for_destruction?</tt>).
  #
  # Saving of the parent, its associations, and the destruction of marked
  # associations, all happen inside a transaction. This should never leave the
  # database in an inconsistent state.
  #
  # If validations for any of the associations fail, their error messages will
  # be applied to the parent.
  #
  # Note that it also means that associations marked for destruction won't
  # be destroyed directly. They will however still be marked for destruction.
  #
  # Note that <tt>:autosave => false</tt> is not same as not declaring <tt>:autosave</tt>.
  # When the <tt>:autosave</tt> option is not present new associations are saved.
  #
  # == Validation
  #
  # Children records are validated unless <tt>:validate</tt> is +false+.
  #
  # == Callbacks
  #
  # Association with autosave option defines several callbacks on your
  # model (before_save, after_create, after_update). Please note that
  # callbacks are executed in the order they were defined in
  # model. You should avoid modyfing the association content, before
  # autosave callbacks are executed. Placing your callbacks after
  # associations is usually a good practice.
  #
  # == Examples
  #
  # === One-to-one Example
  #
  #   class Post
  #     has_one :author, :autosave => true
  #   end
  #
  # Saving changes to the parent and its associated model can now be performed
  # automatically _and_ atomically:
  #
  #   post = Post.find(1)
  #   post.title       # => "The current global position of migrating ducks"
  #   post.author.name # => "alloy"
  #
  #   post.title = "On the migration of ducks"
  #   post.author.name = "Eloy Duran"
  #
  #   post.save
  #   post.reload
  #   post.title       # => "On the migration of ducks"
  #   post.author.name # => "Eloy Duran"
  #
  # Destroying an associated model, as part of the parent's save action, is as
  # simple as marking it for destruction:
  #
  #   post.author.mark_for_destruction
  #   post.author.marked_for_destruction? # => true
  #
  # Note that the model is _not_ yet removed from the database:
  #
  #   id = post.author.id
  #   Author.find_by_id(id).nil? # => false
  #
  #   post.save
  #   post.reload.author # => nil
  #
  # Now it _is_ removed from the database:
  #
  #   Author.find_by_id(id).nil? # => true
  #
  # === One-to-many Example
  #
  # When <tt>:autosave</tt> is not declared new children are saved when their parent is saved:
  #
  #   class Post
  #     has_many :comments # :autosave option is no declared
  #   end
  #
  #   post = Post.new(:title => 'ruby rocks')
  #   post.comments.build(:body => 'hello world')
  #   post.save # => saves both post and comment
  #
  #   post = Post.create(:title => 'ruby rocks')
  #   post.comments.build(:body => 'hello world')
  #   post.save # => saves both post and comment
  #
  #   post = Post.create(:title => 'ruby rocks')
  #   post.comments.create(:body => 'hello world')
  #   post.save # => saves both post and comment
  #
  # When <tt>:autosave</tt> is true all children is saved, no matter whether they are new records:
  #
  #   class Post
  #     has_many :comments, :autosave => true
  #   end
  #
  #   post = Post.create(:title => 'ruby rocks')
  #   post.comments.create(:body => 'hello world')
  #   post.comments[0].body = 'hi everyone'
  #   post.save # => saves both post and comment, with 'hi everyone' as body
  #
  # Destroying one of the associated models as part of the parent's save action
  # is as simple as marking it for destruction:
  #
  #   post.comments.last.mark_for_destruction
  #   post.comments.last.marked_for_destruction? # => true
  #   post.comments.length # => 2
  #
  # Note that the model is _not_ yet removed from the database:
  #
  #   id = post.comments.last.id
  #   Comment.find_by_id(id).nil? # => false
  #
  #   post.save
  #   post.reload.comments.length # => 1
  #
  # Now it _is_ removed from the database:
  #
  #   Comment.find_by_id(id).nil? # => true

  module AutosaveAssociation
    extend ActiveSupport::Concern

    ASSOCIATION_TYPES = %w{ HasOne HasMany BelongsTo HasAndBelongsToMany }

    module AssociationBuilderExtension #:nodoc:
      def self.included(base)
        base.valid_options << :autosave
      end

      def build
        reflection = super
        model.send(:add_autosave_association_callbacks, reflection)
        reflection
      end
    end

    included do
      ASSOCIATION_TYPES.each do |type|
        Associations::Builder.const_get(type).send(:include, AssociationBuilderExtension)
      end
    end

    module ClassMethods
      private

      def define_non_cyclic_method(name, reflection, &block)
        define_method(name) do |*args|
          result = true; @_already_called ||= {}
          # Loop prevention for validation of associations
          unless @_already_called[[name, reflection.name]]
            begin
              @_already_called[[name, reflection.name]]=true
              result = instance_eval(&block)
            ensure
              @_already_called[[name, reflection.name]]=false
            end
          end

          result
        end
      end

      # Adds validation and save callbacks for the association as specified by
      # the +reflection+.
      #
      # For performance reasons, we don't check whether to validate at runtime.
      # However the validation and callback methods are lazy and those methods
      # get created when they are invoked for the very first time. However,
      # this can change, for instance, when using nested attributes, which is
      # called _after_ the association has been defined. Since we don't want
      # the callbacks to get defined multiple times, there are guards that
      # check if the save or validation methods have already been defined
      # before actually defining them.
      def add_autosave_association_callbacks(reflection)
        save_method = :"autosave_associated_records_for_#{reflection.name}"
        validation_method = :"validate_associated_records_for_#{reflection.name}"
        collection = reflection.collection?

        unless method_defined?(save_method)
          if collection
            before_save :before_save_collection_association

            define_non_cyclic_method(save_method, reflection) { save_collection_association(reflection) }
            # Doesn't use after_save as that would save associations added in after_create/after_update twice
            after_create save_method
            after_update save_method
          else
            if reflection.macro == :has_one
              define_method(save_method) { save_has_one_association(reflection) }
              # Configures two callbacks instead of a single after_save so that
              # the model may rely on their execution order relative to its
              # own callbacks.
              #
              # For example, given that after_creates run before after_saves, if
              # we configured instead an after_save there would be no way to fire
              # a custom after_create callback after the child association gets
              # created.
              after_create save_method
              after_update save_method
            else
              define_non_cyclic_method(save_method, reflection) { save_belongs_to_association(reflection) }
              before_save save_method
            end
          end
        end

        if reflection.validate? && !method_defined?(validation_method)
          method = (collection ? :validate_collection_association : :validate_single_association)
          define_non_cyclic_method(validation_method, reflection) { send(method, reflection) }
          validate validation_method
        end
      end
    end

    # Reloads the attributes of the object as usual and clears <tt>marked_for_destruction</tt> flag.
    def reload(options = nil)
      @marked_for_destruction = false
      super
    end

    # Marks this record to be destroyed as part of the parents save transaction.
    # This does _not_ actually destroy the record instantly, rather child record will be destroyed
    # when <tt>parent.save</tt> is called.
    #
    # Only useful if the <tt>:autosave</tt> option on the parent is enabled for this associated model.
    def mark_for_destruction
      @marked_for_destruction = true
    end

    # Returns whether or not this record will be destroyed as part of the parents save transaction.
    #
    # Only useful if the <tt>:autosave</tt> option on the parent is enabled for this associated model.
    def marked_for_destruction?
      @marked_for_destruction
    end

    # Returns whether or not this record has been changed in any way (including whether
    # any of its nested autosave associations are likewise changed)
    def changed_for_autosave?
      new_record? || changed? || marked_for_destruction? || nested_records_changed_for_autosave?
    end

    private

    # Returns the record for an association collection that should be validated
    # or saved. If +autosave+ is +false+ only new records will be returned,
    # unless the parent is/was a new record itself.
    def associated_records_to_validate_or_save(association, new_record, autosave)
      if new_record
        association && association.target
      elsif autosave
        association.target.find_all { |record| record.changed_for_autosave? }
      else
        association.target.find_all { |record| record.new_record? }
      end
    end

    # go through nested autosave associations that are loaded in memory (without loading
    # any new ones), and return true if is changed for autosave
    def nested_records_changed_for_autosave?
      self.class.reflect_on_all_autosave_associations.any? do |reflection|
        association = association_instance_get(reflection.name)
        association && Array.wrap(association.target).any? { |a| a.changed_for_autosave? }
      end
    end

    # Validate the association if <tt>:validate</tt> or <tt>:autosave</tt> is
    # turned on for the association.
    def validate_single_association(reflection)
      association = association_instance_get(reflection.name)
      record      = association && association.reader
      association_valid?(reflection, record) if record
    end

    # Validate the associated records if <tt>:validate</tt> or
    # <tt>:autosave</tt> is turned on for the association specified by
    # +reflection+.
    def validate_collection_association(reflection)
      if association = association_instance_get(reflection.name)
        if records = associated_records_to_validate_or_save(association, new_record?, reflection.options[:autosave])
          records.each { |record| association_valid?(reflection, record) }
        end
      end
    end

    # Returns whether or not the association is valid and applies any errors to
    # the parent, <tt>self</tt>, if it wasn't. Skips any <tt>:autosave</tt>
    # enabled records if they're marked_for_destruction? or destroyed.
    def association_valid?(reflection, record)
      return true if record.destroyed? || record.marked_for_destruction?

      unless valid = record.valid?
        if reflection.options[:autosave]
          record.errors.each do |attribute, message|
            attribute = "#{reflection.name}.#{attribute}"
            errors[attribute] << message
            errors[attribute].uniq!
          end
        else
          errors.add(reflection.name)
        end
      end
      valid
    end

    # Is used as a before_save callback to check while saving a collection
    # association whether or not the parent was a new record before saving.
    def before_save_collection_association
      @new_record_before_save = new_record?
      true
    end

    # Saves any new associated records, or all loaded autosave associations if
    # <tt>:autosave</tt> is enabled on the association.
    #
    # In addition, it destroys all children that were marked for destruction
    # with mark_for_destruction.
    #
    # This all happens inside a transaction, _if_ the Transactions module is included into
    # ActiveRecord::Base after the AutosaveAssociation module, which it does by default.
    def save_collection_association(reflection)
      if association = association_instance_get(reflection.name)
        autosave = reflection.options[:autosave]

        if records = associated_records_to_validate_or_save(association, @new_record_before_save, autosave)
          begin
            records_to_destroy = []

            records.each do |record|
              next if record.destroyed?

              saved = true

              if autosave && record.marked_for_destruction?
                records_to_destroy << record
              elsif autosave != false && (@new_record_before_save || record.new_record?)
                if autosave
                  saved = association.insert_record(record, false)
                else
                  association.insert_record(record) unless reflection.nested?
                end
              elsif autosave
                saved = record.save(:validate => false)
              end

              raise ActiveRecord::Rollback unless saved
            end

            records_to_destroy.each do |record|
              association.proxy.destroy(record)
            end
          rescue
            records.each {|x| IdentityMap.remove(x) } if IdentityMap.enabled?
            raise
          end

        end

        # reconstruct the scope now that we know the owner's id
        association.send(:reset_scope) if association.respond_to?(:reset_scope)
      end
    end

    # Saves the associated record if it's new or <tt>:autosave</tt> is enabled
    # on the association.
    #
    # In addition, it will destroy the association if it was marked for
    # destruction with mark_for_destruction.
    #
    # This all happens inside a transaction, _if_ the Transactions module is included into
    # ActiveRecord::Base after the AutosaveAssociation module, which it does by default.
    def save_has_one_association(reflection)
      association = association_instance_get(reflection.name)
      record      = association && association.load_target
      if record && !record.destroyed?
        autosave = reflection.options[:autosave]

        if autosave && record.marked_for_destruction?
          record.destroy
        else
          key = reflection.options[:primary_key] ? send(reflection.options[:primary_key]) : id
          if autosave != false && (new_record? || record.new_record? || record[reflection.foreign_key] != key || autosave)
            unless reflection.through_reflection
              record[reflection.foreign_key] = key
            end

            saved = record.save(:validate => !autosave)
            raise ActiveRecord::Rollback if !saved && autosave
            saved
          end
        end
      end
    end

    # Saves the associated record if it's new or <tt>:autosave</tt> is enabled.
    #
    # In addition, it will destroy the association if it was marked for destruction.
    def save_belongs_to_association(reflection)
      association = association_instance_get(reflection.name)
      record      = association && association.load_target
      if record && !record.destroyed?
        autosave = reflection.options[:autosave]

        if autosave && record.marked_for_destruction?
          record.destroy
        elsif autosave != false
          saved = record.save(:validate => !autosave) if record.new_record? || (autosave && record.changed_for_autosave?)

          if association.updated?
            association_id = record.send(reflection.options[:primary_key] || :id)
            self[reflection.foreign_key] = association_id
            association.loaded!
          end

          saved if autosave
        end
      end
    end
  end
end
begin
  require 'psych'
rescue LoadError
end

require 'yaml'
require 'set'
require 'thread'
require 'active_support/benchmarkable'
require 'active_support/dependencies'
require 'active_support/descendants_tracker'
require 'active_support/time'
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/class/attribute_accessors'
require 'active_support/core_ext/class/delegating_attributes'
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/array/extract_options'
require 'active_support/core_ext/hash/deep_merge'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/string/behavior'
require 'active_support/core_ext/kernel/singleton_class'
require 'active_support/core_ext/module/delegation'
require 'active_support/core_ext/module/introspection'
require 'active_support/core_ext/object/duplicable'
require 'active_support/core_ext/object/blank'
require 'active_support/deprecation'
require 'arel'
require 'active_record/errors'
require 'active_record/log_subscriber'
require 'active_record/explain_subscriber'

module ActiveRecord #:nodoc:
  # = Active Record
  #
  # Active Record objects don't specify their attributes directly, but rather infer them from
  # the table definition with which they're linked. Adding, removing, and changing attributes
  # and their type is done directly in the database. Any change is instantly reflected in the
  # Active Record objects. The mapping that binds a given Active Record class to a certain
  # database table will happen automatically in most common cases, but can be overwritten for the uncommon ones.
  #
  # See the mapping rules in table_name and the full example in link:files/activerecord/README_rdoc.html for more insight.
  #
  # == Creation
  #
  # Active Records accept constructor parameters either in a hash or as a block. The hash
  # method is especially useful when you're receiving the data from somewhere else, like an
  # HTTP request. It works like this:
  #
  #   user = User.new(:name => "David", :occupation => "Code Artist")
  #   user.name # => "David"
  #
  # You can also use block initialization:
  #
  #   user = User.new do |u|
  #     u.name = "David"
  #     u.occupation = "Code Artist"
  #   end
  #
  # And of course you can just create a bare object and specify the attributes after the fact:
  #
  #   user = User.new
  #   user.name = "David"
  #   user.occupation = "Code Artist"
  #
  # == Conditions
  #
  # Conditions can either be specified as a string, array, or hash representing the WHERE-part of an SQL statement.
  # The array form is to be used when the condition input is tainted and requires sanitization. The string form can
  # be used for statements that don't involve tainted data. The hash form works much like the array form, except
  # only equality and range is possible. Examples:
  #
  #   class User < ActiveRecord::Base
  #     def self.authenticate_unsafely(user_name, password)
  #       where("user_name = '#{user_name}' AND password = '#{password}'").first
  #     end
  #
  #     def self.authenticate_safely(user_name, password)
  #       where("user_name = ? AND password = ?", user_name, password).first
  #     end
  #
  #     def self.authenticate_safely_simply(user_name, password)
  #       where(:user_name => user_name, :password => password).first
  #     end
  #   end
  #
  # The <tt>authenticate_unsafely</tt> method inserts the parameters directly into the query
  # and is thus susceptible to SQL-injection attacks if the <tt>user_name</tt> and +password+
  # parameters come directly from an HTTP request. The <tt>authenticate_safely</tt> and
  # <tt>authenticate_safely_simply</tt> both will sanitize the <tt>user_name</tt> and +password+
  # before inserting them in the query, which will ensure that an attacker can't escape the
  # query and fake the login (or worse).
  #
  # When using multiple parameters in the conditions, it can easily become hard to read exactly
  # what the fourth or fifth question mark is supposed to represent. In those cases, you can
  # resort to named bind variables instead. That's done by replacing the question marks with
  # symbols and supplying a hash with values for the matching symbol keys:
  #
  #   Company.where(
  #     "id = :id AND name = :name AND division = :division AND created_at > :accounting_date",
  #     { :id => 3, :name => "37signals", :division => "First", :accounting_date => '2005-01-01' }
  #   ).first
  #
  # Similarly, a simple hash without a statement will generate conditions based on equality with the SQL AND
  # operator. For instance:
  #
  #   Student.where(:first_name => "Harvey", :status => 1)
  #   Student.where(params[:student])
  #
  # A range may be used in the hash to use the SQL BETWEEN operator:
  #
  #   Student.where(:grade => 9..12)
  #
  # An array may be used in the hash to use the SQL IN operator:
  #
  #   Student.where(:grade => [9,11,12])
  #
  # When joining tables, nested hashes or keys written in the form 'table_name.column_name'
  # can be used to qualify the table name of a particular condition. For instance:
  #
  #   Student.joins(:schools).where(:schools => { :category => 'public' })
  #   Student.joins(:schools).where('schools.category' => 'public' )
  #
  # == Overwriting default accessors
  #
  # All column values are automatically available through basic accessors on the Active Record
  # object, but sometimes you want to specialize this behavior. This can be done by overwriting
  # the default accessors (using the same name as the attribute) and calling
  # <tt>read_attribute(attr_name)</tt> and <tt>write_attribute(attr_name, value)</tt> to actually
  # change things.
  #
  #   class Song < ActiveRecord::Base
  #     # Uses an integer of seconds to hold the length of the song
  #
  #     def length=(minutes)
  #       write_attribute(:length, minutes.to_i * 60)
  #     end
  #
  #     def length
  #       read_attribute(:length) / 60
  #     end
  #   end
  #
  # You can alternatively use <tt>self[:attribute]=(value)</tt> and <tt>self[:attribute]</tt>
  # instead of <tt>write_attribute(:attribute, value)</tt> and <tt>read_attribute(:attribute)</tt>.
  #
  # == Attribute query methods
  #
  # In addition to the basic accessors, query methods are also automatically available on the Active Record object.
  # Query methods allow you to test whether an attribute value is present.
  #
  # For example, an Active Record User with the <tt>name</tt> attribute has a <tt>name?</tt> method that you can call
  # to determine whether the user has a name:
  #
  #   user = User.new(:name => "David")
  #   user.name? # => true
  #
  #   anonymous = User.new(:name => "")
  #   anonymous.name? # => false
  #
  # == Accessing attributes before they have been typecasted
  #
  # Sometimes you want to be able to read the raw attribute data without having the column-determined
  # typecast run its course first. That can be done by using the <tt><attribute>_before_type_cast</tt>
  # accessors that all attributes have. For example, if your Account model has a <tt>balance</tt> attribute,
  # you can call <tt>account.balance_before_type_cast</tt> or <tt>account.id_before_type_cast</tt>.
  #
  # This is especially useful in validation situations where the user might supply a string for an
  # integer field and you want to display the original string back in an error message. Accessing the
  # attribute normally would typecast the string to 0, which isn't what you want.
  #
  # == Dynamic attribute-based finders
  #
  # Dynamic attribute-based finders are a cleaner way of getting (and/or creating) objects
  # by simple queries without turning to SQL. They work by appending the name of an attribute
  # to <tt>find_by_</tt>, <tt>find_last_by_</tt>, or <tt>find_all_by_</tt> and thus produces finders
  # like <tt>Person.find_by_user_name</tt>, <tt>Person.find_all_by_last_name</tt>, and
  # <tt>Payment.find_by_transaction_id</tt>. Instead of writing
  # <tt>Person.where(:user_name => user_name).first</tt>, you just do <tt>Person.find_by_user_name(user_name)</tt>.
  # And instead of writing <tt>Person.where(:last_name => last_name).all</tt>, you just do
  # <tt>Person.find_all_by_last_name(last_name)</tt>.
  #
  # It's possible to add an exclamation point (!) on the end of the dynamic finders to get them to raise an
  # <tt>ActiveRecord::RecordNotFound</tt> error if they do not return any records,
  # like <tt>Person.find_by_last_name!</tt>.
  #
  # It's also possible to use multiple attributes in the same find by separating them with "_and_".
  #
  #  Person.where(:user_name => user_name, :password => password).first
  #  Person.find_by_user_name_and_password(user_name, password) # with dynamic finder
  #
  # It's even possible to call these dynamic finder methods on relations and named scopes.
  #
  #   Payment.order("created_on").find_all_by_amount(50)
  #   Payment.pending.find_last_by_amount(100)
  #
  # The same dynamic finder style can be used to create the object if it doesn't already exist.
  # This dynamic finder is called with <tt>find_or_create_by_</tt> and will return the object if
  # it already exists and otherwise creates it, then returns it. Protected attributes won't be set
  # unless they are given in a block.
  #
  #   # No 'Summer' tag exists
  #   Tag.find_or_create_by_name("Summer") # equal to Tag.create(:name => "Summer")
  #
  #   # Now the 'Summer' tag does exist
  #   Tag.find_or_create_by_name("Summer") # equal to Tag.find_by_name("Summer")
  #
  #   # Now 'Bob' exist and is an 'admin'
  #   User.find_or_create_by_name('Bob', :age => 40) { |u| u.admin = true }
  #
  # Adding an exclamation point (!) on to the end of <tt>find_or_create_by_</tt> will
  # raise an <tt>ActiveRecord::RecordInvalid</tt> error if the new record is invalid.
  #
  # Use the <tt>find_or_initialize_by_</tt> finder if you want to return a new record without
  # saving it first. Protected attributes won't be set unless they are given in a block.
  #
  #   # No 'Winter' tag exists
  #   winter = Tag.find_or_initialize_by_name("Winter")
  #   winter.persisted? # false
  #
  # To find by a subset of the attributes to be used for instantiating a new object, pass a hash instead of
  # a list of parameters.
  #
  #   Tag.find_or_create_by_name(:name => "rails", :creator => current_user)
  #
  # That will either find an existing tag named "rails", or create a new one while setting the
  # user that created it.
  #
  # Just like <tt>find_by_*</tt>, you can also use <tt>scoped_by_*</tt> to retrieve data. The good thing about
  # using this feature is that the very first time result is returned using <tt>method_missing</tt> technique
  # but after that the method is declared on the class. Henceforth <tt>method_missing</tt> will not be hit.
  #
  #  User.scoped_by_user_name('David')
  #
  # == Saving arrays, hashes, and other non-mappable objects in text columns
  #
  # Active Record can serialize any object in text columns using YAML. To do so, you must
  # specify this with a call to the class method +serialize+.
  # This makes it possible to store arrays, hashes, and other non-mappable objects without doing
  # any additional work.
  #
  #   class User < ActiveRecord::Base
  #     serialize :preferences
  #   end
  #
  #   user = User.create(:preferences => { "background" => "black", "display" => large })
  #   User.find(user.id).preferences # => { "background" => "black", "display" => large }
  #
  # You can also specify a class option as the second parameter that'll raise an exception
  # if a serialized object is retrieved as a descendant of a class not in the hierarchy.
  #
  #   class User < ActiveRecord::Base
  #     serialize :preferences, Hash
  #   end
  #
  #   user = User.create(:preferences => %w( one two three ))
  #   User.find(user.id).preferences    # raises SerializationTypeMismatch
  #
  # When you specify a class option, the default value for that attribute will be a new
  # instance of that class.
  #
  #   class User < ActiveRecord::Base
  #     serialize :preferences, OpenStruct
  #   end
  #
  #   user = User.new
  #   user.preferences.theme_color = "red"
  #
  #
  # == Single table inheritance
  #
  # Active Record allows inheritance by storing the name of the class in a column that by
  # default is named "type" (can be changed by overwriting <tt>Base.inheritance_column</tt>).
  # This means that an inheritance looking like this:
  #
  #   class Company < ActiveRecord::Base; end
  #   class Firm < Company; end
  #   class Client < Company; end
  #   class PriorityClient < Client; end
  #
  # When you do <tt>Firm.create(:name => "37signals")</tt>, this record will be saved in
  # the companies table with type = "Firm". You can then fetch this row again using
  # <tt>Company.where(:name => '37signals').first</tt> and it will return a Firm object.
  #
  # If you don't have a type column defined in your table, single-table inheritance won't
  # be triggered. In that case, it'll work just like normal subclasses with no special magic
  # for differentiating between them or reloading the right type with find.
  #
  # Note, all the attributes for all the cases are kept in the same table. Read more:
  # http://www.martinfowler.com/eaaCatalog/singleTableInheritance.html
  #
  # == Connection to multiple databases in different models
  #
  # Connections are usually created through ActiveRecord::Base.establish_connection and retrieved
  # by ActiveRecord::Base.connection. All classes inheriting from ActiveRecord::Base will use this
  # connection. But you can also set a class-specific connection. For example, if Course is an
  # ActiveRecord::Base, but resides in a different database, you can just say <tt>Course.establish_connection</tt>
  # and Course and all of its subclasses will use this connection instead.
  #
  # This feature is implemented by keeping a connection pool in ActiveRecord::Base that is
  # a Hash indexed by the class. If a connection is requested, the retrieve_connection method
  # will go up the class-hierarchy until a connection is found in the connection pool.
  #
  # == Exceptions
  #
  # * ActiveRecordError - Generic error class and superclass of all other errors raised by Active Record.
  # * AdapterNotSpecified - The configuration hash used in <tt>establish_connection</tt> didn't include an
  #   <tt>:adapter</tt> key.
  # * AdapterNotFound - The <tt>:adapter</tt> key used in <tt>establish_connection</tt> specified a
  #   non-existent adapter
  #   (or a bad spelling of an existing one).
  # * AssociationTypeMismatch - The object assigned to the association wasn't of the type
  #   specified in the association definition.
  # * SerializationTypeMismatch - The serialized object wasn't of the class specified as the second parameter.
  # * ConnectionNotEstablished+ - No connection has been established. Use <tt>establish_connection</tt>
  #   before querying.
  # * RecordNotFound - No record responded to the +find+ method. Either the row with the given ID doesn't exist
  #   or the row didn't meet the additional restrictions. Some +find+ calls do not raise this exception to signal
  #   nothing was found, please check its documentation for further details.
  # * StatementInvalid - The database server rejected the SQL statement. The precise error is added in the message.
  # * MultiparameterAssignmentErrors - Collection of errors that occurred during a mass assignment using the
  #   <tt>attributes=</tt> method. The +errors+ property of this exception contains an array of
  #   AttributeAssignmentError
  #   objects that should be inspected to determine which attributes triggered the errors.
  # * AttributeAssignmentError - An error occurred while doing a mass assignment through the
  #   <tt>attributes=</tt> method.
  #   You can inspect the +attribute+ property of the exception object to determine which attribute
  #   triggered the error.
  #
  # *Note*: The attributes listed are class-level attributes (accessible from both the class and instance level).
  # So it's possible to assign a logger to the class through <tt>Base.logger=</tt> which will then be used by all
  # instances in the current object space.
  class Base
    ##
    # :singleton-method:
    # Accepts a logger conforming to the interface of Log4r or the default Ruby 1.8+ Logger class,
    # which is then passed on to any new database connections made and which can be retrieved on both
    # a class and instance level by calling +logger+.
    cattr_accessor :logger, :instance_writer => false

    ##
    # :singleton-method:
    # Contains the database configuration - as is typically stored in config/database.yml -
    # as a Hash.
    #
    # For example, the following database.yml...
    #
    #   development:
    #     adapter: sqlite3
    #     database: db/development.sqlite3
    #
    #   production:
    #     adapter: sqlite3
    #     database: db/production.sqlite3
    #
    # ...would result in ActiveRecord::Base.configurations to look like this:
    #
    #   {
    #      'development' => {
    #         'adapter'  => 'sqlite3',
    #         'database' => 'db/development.sqlite3'
    #      },
    #      'production' => {
    #         'adapter'  => 'sqlite3',
    #         'database' => 'db/production.sqlite3'
    #      }
    #   }
    cattr_accessor :configurations, :instance_writer => false
    @@configurations = {}

    ##
    # :singleton-method:
    # Determines whether to use Time.local (using :local) or Time.utc (using :utc) when pulling
    # dates and times from the database. This is set to :local by default.
    cattr_accessor :default_timezone, :instance_writer => false
    @@default_timezone = :local

    ##
    # :singleton-method:
    # Specifies the format to use when dumping the database schema with Rails'
    # Rakefile. If :sql, the schema is dumped as (potentially database-
    # specific) SQL statements. If :ruby, the schema is dumped as an
    # ActiveRecord::Schema file which can be loaded into any database that
    # supports migrations. Use :ruby if you want to have different database
    # adapters for, e.g., your development and test environments.
    cattr_accessor :schema_format , :instance_writer => false
    @@schema_format = :ruby

    ##
    # :singleton-method:
    # Specify whether or not to use timestamps for migration versions
    cattr_accessor :timestamped_migrations , :instance_writer => false
    @@timestamped_migrations = true

    class << self # Class methods
      def inherited(child_class) #:nodoc:
        child_class.initialize_generated_modules
        super
      end

      def initialize_generated_modules #:nodoc:
        @attribute_methods_mutex = Mutex.new

        # force attribute methods to be higher in inheritance hierarchy than other generated methods
        generated_attribute_methods
        generated_feature_methods
      end

      def generated_feature_methods
        @generated_feature_methods ||= begin
          mod = const_set(:GeneratedFeatureMethods, Module.new)
          include mod
          mod
        end
      end

      # Returns a string like 'Post(id:integer, title:string, body:text)'
      def inspect
        if self == Base
          super
        elsif abstract_class?
          "#{super}(abstract)"
        elsif table_exists?
          attr_list = columns.map { |c| "#{c.name}: #{c.type}" } * ', '
          "#{super}(#{attr_list})"
        else
          "#{super}(Table doesn't exist)"
        end
      end

      # Overwrite the default class equality method to provide support for association proxies.
      def ===(object)
        object.is_a?(self)
      end

      def arel_table
        @arel_table ||= Arel::Table.new(table_name, arel_engine)
      end

      def arel_engine
        @arel_engine ||= begin
          if self == ActiveRecord::Base
            ActiveRecord::Base
          else
            connection_handler.retrieve_connection_pool(self) ? self : superclass.arel_engine
          end
        end
      end

      private

      def relation #:nodoc:
        relation = Relation.new(self, arel_table)

        if finder_needs_type_condition?
          relation.where(type_condition).create_with(inheritance_column.to_sym => sti_name)
        else
          relation
        end
      end
    end

    public
      # New objects can be instantiated as either empty (pass no construction parameter) or pre-set with
      # attributes but not yet saved (pass a hash with key names matching the associated table column names).
      # In both instances, valid attribute keys are determined by the column names of the associated table --
      # hence you can't have attributes that aren't part of the table columns.
      #
      # +initialize+ respects mass-assignment security and accepts either +:as+ or +:without_protection+ options
      # in the +options+ parameter.
      #
      # ==== Examples
      #   # Instantiates a single new object
      #   User.new(:first_name => 'Jamie')
      #
      #   # Instantiates a single new object using the :admin mass-assignment security role
      #   User.new({ :first_name => 'Jamie', :is_admin => true }, :as => :admin)
      #
      #   # Instantiates a single new object bypassing mass-assignment security
      #   User.new({ :first_name => 'Jamie', :is_admin => true }, :without_protection => true)
      def initialize(attributes = nil, options = {})
        @attributes = self.class.initialize_attributes(self.class.column_defaults.dup)
        @association_cache = {}
        @aggregation_cache = {}
        @attributes_cache = {}
        @new_record = true
        @readonly = false
        @destroyed = false
        @marked_for_destruction = false
        @previously_changed = {}
        @changed_attributes = {}

        ensure_proper_type

        populate_with_current_scope_attributes

        assign_attributes(attributes, options) if attributes

        yield self if block_given?
        run_callbacks :initialize
      end

      # Initialize an empty model object from +coder+. +coder+ must contain
      # the attributes necessary for initializing an empty model object. For
      # example:
      #
      #   class Post < ActiveRecord::Base
      #   end
      #
      #   post = Post.allocate
      #   post.init_with('attributes' => { 'title' => 'hello world' })
      #   post.title # => 'hello world'
      def init_with(coder)
        @attributes = self.class.initialize_attributes(coder['attributes'])
        @relation = nil

        @attributes_cache, @previously_changed, @changed_attributes = {}, {}, {}
        @association_cache = {}
        @aggregation_cache = {}
        @readonly = @destroyed = @marked_for_destruction = false
        @new_record = false
        run_callbacks :find
        run_callbacks :initialize

        self
      end

      # Duped objects have no id assigned and are treated as new records. Note
      # that this is a "shallow" copy as it copies the object's attributes
      # only, not its associations. The extent of a "deep" copy is application
      # specific and is therefore left to the application to implement according
      # to its need.
      # The dup method does not preserve the timestamps (created|updated)_(at|on).
      def initialize_dup(other)
        cloned_attributes = other.clone_attributes(:read_attribute_before_type_cast)
        self.class.initialize_attributes(cloned_attributes, :serialized => false)

        cloned_attributes.delete(self.class.primary_key)

        @attributes = cloned_attributes

        _run_after_initialize_callbacks if respond_to?(:_run_after_initialize_callbacks)

        @changed_attributes = {}
        self.class.column_defaults.each do |attr, orig_value|
          @changed_attributes[attr] = orig_value if _field_changed?(attr, orig_value, @attributes[attr])
        end

        @aggregation_cache = {}
        @association_cache = {}
        @attributes_cache = {}
        @new_record  = true

        ensure_proper_type
        populate_with_current_scope_attributes
        super
      end

      # Backport dup from 1.9 so that initialize_dup() gets called
      unless Object.respond_to?(:initialize_dup)
        def dup # :nodoc:
          copy = super
          copy.initialize_dup(self)
          copy
        end
      end

      # Populate +coder+ with attributes about this record that should be
      # serialized. The structure of +coder+ defined in this method is
      # guaranteed to match the structure of +coder+ passed to the +init_with+
      # method.
      #
      # Example:
      #
      #   class Post < ActiveRecord::Base
      #   end
      #   coder = {}
      #   Post.new.encode_with(coder)
      #   coder # => { 'id' => nil, ... }
      def encode_with(coder)
        coder['attributes'] = attributes
      end

      # Returns true if +comparison_object+ is the same exact object, or +comparison_object+
      # is of the same type and +self+ has an ID and it is equal to +comparison_object.id+.
      #
      # Note that new records are different from any other record by definition, unless the
      # other record is the receiver itself. Besides, if you fetch existing records with
      # +select+ and leave the ID out, you're on your own, this predicate will return false.
      #
      # Note also that destroying a record preserves its ID in the model instance, so deleted
      # models are still comparable.
      def ==(comparison_object)
        super ||
          comparison_object.instance_of?(self.class) &&
          id.present? &&
          comparison_object.id == id
      end
      alias :eql? :==

      # Delegates to id in order to allow two records of the same type and id to work with something like:
      #   [ Person.find(1), Person.find(2), Person.find(3) ] & [ Person.find(1), Person.find(4) ] # => [ Person.find(1) ]
      def hash
        id.hash
      end

      # Freeze the attributes hash such that associations are still accessible, even on destroyed records.
      def freeze
        @attributes.freeze; self
      end

      # Returns +true+ if the attributes hash has been frozen.
      def frozen?
        @attributes.frozen?
      end

      # Allows sort on objects
      def <=>(other_object)
        if other_object.is_a?(self.class)
          self.to_key <=> other_object.to_key
        else
          nil
        end
      end

      # Returns +true+ if the record is read only. Records loaded through joins with piggy-back
      # attributes will be marked as read only since they cannot be saved.
      def readonly?
        @readonly
      end

      # Marks this record as read only.
      def readonly!
        @readonly = true
      end

      # Returns the contents of the record as a nicely formatted string.
      def inspect
        inspection = if @attributes
                       self.class.column_names.collect { |name|
                         if has_attribute?(name)
                           "#{name}: #{attribute_for_inspect(name)}"
                         end
                       }.compact.join(", ")
                     else
                       "not initialized"
                     end
        "#<#{self.class} #{inspection}>"
      end

      # Hackery to accomodate Syck. Remove for 4.0.
      def to_yaml(opts = {}) #:nodoc:
        if YAML.const_defined?(:ENGINE) && !YAML::ENGINE.syck?
          super
        else
          coder = {}
          encode_with(coder)
          YAML.quick_emit(self, opts) do |out|
            out.map(taguri, to_yaml_style) do |map|
              coder.each { |k, v| map.add(k, v) }
            end
          end
        end
      end

      # Hackery to accomodate Syck. Remove for 4.0.
      def yaml_initialize(tag, coder) #:nodoc:
        init_with(coder)
      end

    private

      # Under Ruby 1.9, Array#flatten will call #to_ary (recursively) on each of the elements
      # of the array, and then rescues from the possible NoMethodError. If those elements are
      # ActiveRecord::Base's, then this triggers the various method_missing's that we have,
      # which significantly impacts upon performance.
      #
      # So we can avoid the method_missing hit by explicitly defining #to_ary as nil here.
      #
      # See also http://tenderlovemaking.com/2011/06/28/til-its-ok-to-return-nil-from-to_ary/
      def to_ary # :nodoc:
        nil
      end

    include ActiveRecord::Persistence
    extend ActiveModel::Naming
    extend QueryCache::ClassMethods
    extend ActiveSupport::Benchmarkable
    extend ActiveSupport::DescendantsTracker

    extend Querying
    include ReadonlyAttributes
    include ModelSchema
    extend Translation
    include Inheritance
    include Scoping
    extend DynamicMatchers
    include Sanitization
    include AttributeAssignment
    include ActiveModel::Conversion
    include Integration
    include Validations
    extend CounterCache
    include Locking::Optimistic, Locking::Pessimistic
    include AttributeMethods
    include Callbacks, ActiveModel::Observing, Timestamp
    include Associations
    include IdentityMap
    include ActiveModel::SecurePassword
    extend Explain

    # AutosaveAssociation needs to be included before Transactions, because we want
    # #save_with_autosave_associations to be wrapped inside a transaction.
    include AutosaveAssociation, NestedAttributes
    include Aggregations, Transactions, Reflection, Serialization, Store
  end
end

require 'active_record/connection_adapters/abstract/connection_specification'
ActiveSupport.run_load_hooks(:active_record, ActiveRecord::Base)
require 'active_support/core_ext/array/wrap'

module ActiveRecord
  # = Active Record Callbacks
  #
  # Callbacks are hooks into the life cycle of an Active Record object that allow you to trigger logic
  # before or after an alteration of the object state. This can be used to make sure that associated and
  # dependent objects are deleted when +destroy+ is called (by overwriting +before_destroy+) or to massage attributes
  # before they're validated (by overwriting +before_validation+). As an example of the callbacks initiated, consider
  # the <tt>Base#save</tt> call for a new record:
  #
  # * (-) <tt>save</tt>
  # * (-) <tt>valid</tt>
  # * (1) <tt>before_validation</tt>
  # * (-) <tt>validate</tt>
  # * (2) <tt>after_validation</tt>
  # * (3) <tt>before_save</tt>
  # * (4) <tt>before_create</tt>
  # * (-) <tt>create</tt>
  # * (5) <tt>after_create</tt>
  # * (6) <tt>after_save</tt>
  # * (7) <tt>after_commit</tt>
  #
  # Also, an <tt>after_rollback</tt> callback can be configured to be triggered whenever a rollback is issued.
  # Check out <tt>ActiveRecord::Transactions</tt> for more details about <tt>after_commit</tt> and
  # <tt>after_rollback</tt>.
  #
  # Lastly an <tt>after_find</tt> and <tt>after_initialize</tt> callback is triggered for each object that 
  # is found and instantiated by a finder, with <tt>after_initialize</tt> being triggered after new objects
  # are instantiated as well.
  #
  # That's a total of twelve callbacks, which gives you immense power to react and prepare for each state in the
  # Active Record life cycle. The sequence for calling <tt>Base#save</tt> for an existing record is similar,
  # except that each <tt>_create</tt> callback is replaced by the corresponding <tt>_update</tt> callback.
  #
  # Examples:
  #   class CreditCard < ActiveRecord::Base
  #     # Strip everything but digits, so the user can specify "555 234 34" or
  #     # "5552-3434" or both will mean "55523434"
  #     before_validation(:on => :create) do
  #       self.number = number.gsub(/[^0-9]/, "") if attribute_present?("number")
  #     end
  #   end
  #
  #   class Subscription < ActiveRecord::Base
  #     before_create :record_signup
  #
  #     private
  #       def record_signup
  #         self.signed_up_on = Date.today
  #       end
  #   end
  #
  #   class Firm < ActiveRecord::Base
  #     # Destroys the associated clients and people when the firm is destroyed
  #     before_destroy { |record| Person.destroy_all "firm_id = #{record.id}"   }
  #     before_destroy { |record| Client.destroy_all "client_of = #{record.id}" }
  #   end
  #
  # == Inheritable callback queues
  #
  # Besides the overwritable callback methods, it's also possible to register callbacks through the
  # use of the callback macros. Their main advantage is that the macros add behavior into a callback
  # queue that is kept intact down through an inheritance hierarchy.
  #
  #   class Topic < ActiveRecord::Base
  #     before_destroy :destroy_author
  #   end
  #
  #   class Reply < Topic
  #     before_destroy :destroy_readers
  #   end
  #
  # Now, when <tt>Topic#destroy</tt> is run only +destroy_author+ is called. When <tt>Reply#destroy</tt> is
  # run, both +destroy_author+ and +destroy_readers+ are called. Contrast this to the following situation
  # where the +before_destroy+ method is overridden:
  #
  #   class Topic < ActiveRecord::Base
  #     def before_destroy() destroy_author end
  #   end
  #
  #   class Reply < Topic
  #     def before_destroy() destroy_readers end
  #   end
  #
  # In that case, <tt>Reply#destroy</tt> would only run +destroy_readers+ and _not_ +destroy_author+.
  # So, use the callback macros when you want to ensure that a certain callback is called for the entire
  # hierarchy, and use the regular overwriteable methods when you want to leave it up to each descendant
  # to decide whether they want to call +super+ and trigger the inherited callbacks.
  #
  # *IMPORTANT:* In order for inheritance to work for the callback queues, you must specify the
  # callbacks before specifying the associations. Otherwise, you might trigger the loading of a
  # child before the parent has registered the callbacks and they won't be inherited.
  #
  # == Types of callbacks
  #
  # There are four types of callbacks accepted by the callback macros: Method references (symbol), callback objects,
  # inline methods (using a proc), and inline eval methods (using a string). Method references and callback objects
  # are the recommended approaches, inline methods using a proc are sometimes appropriate (such as for
  # creating mix-ins), and inline eval methods are deprecated.
  #
  # The method reference callbacks work by specifying a protected or private method available in the object, like this:
  #
  #   class Topic < ActiveRecord::Base
  #     before_destroy :delete_parents
  #
  #     private
  #       def delete_parents
  #         self.class.delete_all "parent_id = #{id}"
  #       end
  #   end
  #
  # The callback objects have methods named after the callback called with the record as the only parameter, such as:
  #
  #   class BankAccount < ActiveRecord::Base
  #     before_save      EncryptionWrapper.new
  #     after_save       EncryptionWrapper.new
  #     after_initialize EncryptionWrapper.new
  #   end
  #
  #   class EncryptionWrapper
  #     def before_save(record)
  #       record.credit_card_number = encrypt(record.credit_card_number)
  #     end
  #
  #     def after_save(record)
  #       record.credit_card_number = decrypt(record.credit_card_number)
  #     end
  #
  #     alias_method :after_find, :after_save
  #
  #     private
  #       def encrypt(value)
  #         # Secrecy is committed
  #       end
  #
  #       def decrypt(value)
  #         # Secrecy is unveiled
  #       end
  #   end
  #
  # So you specify the object you want messaged on a given callback. When that callback is triggered, the object has
  # a method by the name of the callback messaged. You can make these callbacks more flexible by passing in other
  # initialization data such as the name of the attribute to work with:
  #
  #   class BankAccount < ActiveRecord::Base
  #     before_save      EncryptionWrapper.new("credit_card_number")
  #     after_save       EncryptionWrapper.new("credit_card_number")
  #     after_initialize EncryptionWrapper.new("credit_card_number")
  #   end
  #
  #   class EncryptionWrapper
  #     def initialize(attribute)
  #       @attribute = attribute
  #     end
  #
  #     def before_save(record)
  #       record.send("#{@attribute}=", encrypt(record.send("#{@attribute}")))
  #     end
  #
  #     def after_save(record)
  #       record.send("#{@attribute}=", decrypt(record.send("#{@attribute}")))
  #     end
  #
  #     alias_method :after_find, :after_save
  #
  #     private
  #       def encrypt(value)
  #         # Secrecy is committed
  #       end
  #
  #       def decrypt(value)
  #         # Secrecy is unveiled
  #       end
  #   end
  #
  # The callback macros usually accept a symbol for the method they're supposed to run, but you can also
  # pass a "method string", which will then be evaluated within the binding of the callback. Example:
  #
  #   class Topic < ActiveRecord::Base
  #     before_destroy 'self.class.delete_all "parent_id = #{id}"'
  #   end
  #
  # Notice that single quotes (') are used so the <tt>#{id}</tt> part isn't evaluated until the callback
  # is triggered. Also note that these inline callbacks can be stacked just like the regular ones:
  #
  #   class Topic < ActiveRecord::Base
  #     before_destroy 'self.class.delete_all "parent_id = #{id}"',
  #                    'puts "Evaluated after parents are destroyed"'
  #   end
  #
  # == <tt>before_validation*</tt> returning statements
  #
  # If the returning value of a +before_validation+ callback can be evaluated to +false+, the process will be
  # aborted and <tt>Base#save</tt> will return +false+. If Base#save! is called it will raise a
  # ActiveRecord::RecordInvalid exception. Nothing will be appended to the errors object.
  #
  # == Canceling callbacks
  #
  # If a <tt>before_*</tt> callback returns +false+, all the later callbacks and the associated action are
  # cancelled. If an <tt>after_*</tt> callback returns +false+, all the later callbacks are cancelled.
  # Callbacks are generally run in the order they are defined, with the exception of callbacks defined as
  # methods on the model, which are called last.
  #
  # == Transactions
  #
  # The entire callback chain of a +save+, <tt>save!</tt>, or +destroy+ call runs
  # within a transaction. That includes <tt>after_*</tt> hooks. If everything
  # goes fine a COMMIT is executed once the chain has been completed.
  #
  # If a <tt>before_*</tt> callback cancels the action a ROLLBACK is issued. You
  # can also trigger a ROLLBACK raising an exception in any of the callbacks,
  # including <tt>after_*</tt> hooks. Note, however, that in that case the client
  # needs to be aware of it because an ordinary +save+ will raise such exception
  # instead of quietly returning +false+.
  #
  # == Debugging callbacks
  # 
  # The callback chain is accessible via the <tt>_*_callbacks</tt> method on an object. ActiveModel Callbacks support 
  # <tt>:before</tt>, <tt>:after</tt> and <tt>:around</tt> as values for the <tt>kind</tt> property. The <tt>kind</tt> property
  # defines what part of the chain the callback runs in.
  # 
  # To find all callbacks in the before_save callback chain: 
  # 
  #   Topic._save_callbacks.select { |cb| cb.kind.eql?(:before) }
  # 
  # Returns an array of callback objects that form the before_save chain.
  # 
  # To further check if the before_save chain contains a proc defined as <tt>rest_when_dead</tt> use the <tt>filter</tt> property of the callback object:
  # 
  #   Topic._save_callbacks.select { |cb| cb.kind.eql?(:before) }.collect(&:filter).include?(:rest_when_dead)
  # 
  # Returns true or false depending on whether the proc is contained in the before_save callback chain on a Topic model.
  # 
  module Callbacks
    extend ActiveSupport::Concern

    CALLBACKS = [
      :after_initialize, :after_find, :after_touch, :before_validation, :after_validation,
      :before_save, :around_save, :after_save, :before_create, :around_create,
      :after_create, :before_update, :around_update, :after_update,
      :before_destroy, :around_destroy, :after_destroy, :after_commit, :after_rollback
    ]

    included do
      extend ActiveModel::Callbacks
      include ActiveModel::Validations::Callbacks

      define_model_callbacks :initialize, :find, :touch, :only => :after
      define_model_callbacks :save, :create, :update, :destroy
    end

    def destroy #:nodoc:
      run_callbacks(:destroy) { super }
    end

    def touch(*) #:nodoc:
      run_callbacks(:touch) { super }
    end

  private

    def create_or_update #:nodoc:
      run_callbacks(:save) { super }
    end

    def create #:nodoc:
      run_callbacks(:create) { super }
    end

    def update(*) #:nodoc:
      run_callbacks(:update) { super }
    end
  end
end
module ActiveRecord
  # :stopdoc:
  module Coders
    class YAMLColumn
      RESCUE_ERRORS = [ ArgumentError ]

      if defined?(Psych) && defined?(Psych::SyntaxError)
        RESCUE_ERRORS << Psych::SyntaxError
      end

      attr_accessor :object_class

      def initialize(object_class = Object)
        @object_class = object_class
      end

      def dump(obj)
        YAML.dump obj
      end

      def load(yaml)
        return object_class.new if object_class != Object && yaml.nil?
        return yaml unless yaml.is_a?(String) && yaml =~ /^---/
        begin
          obj = YAML.load(yaml)

          unless obj.is_a?(object_class) || obj.nil?
            raise SerializationTypeMismatch,
              "Attribute was supposed to be a #{object_class}, but was a #{obj.class}"
          end
          obj ||= object_class.new if object_class != Object

          obj
        rescue *RESCUE_ERRORS
          yaml
        end
      end
    end
  end
  # :startdoc
end
require 'thread'
require 'monitor'
require 'set'
require 'active_support/core_ext/module/deprecation'

module ActiveRecord
  # Raised when a connection could not be obtained within the connection
  # acquisition timeout period.
  class ConnectionTimeoutError < ConnectionNotEstablished
  end

  module ConnectionAdapters
    # Connection pool base class for managing Active Record database
    # connections.
    #
    # == Introduction
    #
    # A connection pool synchronizes thread access to a limited number of
    # database connections. The basic idea is that each thread checks out a
    # database connection from the pool, uses that connection, and checks the
    # connection back in. ConnectionPool is completely thread-safe, and will
    # ensure that a connection cannot be used by two threads at the same time,
    # as long as ConnectionPool's contract is correctly followed. It will also
    # handle cases in which there are more threads than connections: if all
    # connections have been checked out, and a thread tries to checkout a
    # connection anyway, then ConnectionPool will wait until some other thread
    # has checked in a connection.
    #
    # == Obtaining (checking out) a connection
    #
    # Connections can be obtained and used from a connection pool in several
    # ways:
    #
    # 1. Simply use ActiveRecord::Base.connection as with Active Record 2.1 and
    #    earlier (pre-connection-pooling). Eventually, when you're done with
    #    the connection(s) and wish it to be returned to the pool, you call
    #    ActiveRecord::Base.clear_active_connections!. This will be the
    #    default behavior for Active Record when used in conjunction with
    #    Action Pack's request handling cycle.
    # 2. Manually check out a connection from the pool with
    #    ActiveRecord::Base.connection_pool.checkout. You are responsible for
    #    returning this connection to the pool when finished by calling
    #    ActiveRecord::Base.connection_pool.checkin(connection).
    # 3. Use ActiveRecord::Base.connection_pool.with_connection(&block), which
    #    obtains a connection, yields it as the sole argument to the block,
    #    and returns it to the pool after the block completes.
    #
    # Connections in the pool are actually AbstractAdapter objects (or objects
    # compatible with AbstractAdapter's interface).
    #
    # == Options
    #
    # There are two connection-pooling-related options that you can add to
    # your database connection configuration:
    #
    # * +pool+: number indicating size of connection pool (default 5)
    # * +checkout _timeout+: number of seconds to block and wait for a 
    #   connection before giving up and raising a timeout error 
    #   (default 5 seconds). ('wait_timeout' supported for backwards
    #   compatibility, but conflicts with key used for different purpose
    #   by mysql2 adapter). 
    class ConnectionPool
      include MonitorMixin

      attr_accessor :automatic_reconnect
      attr_reader :spec, :connections

      # Creates a new ConnectionPool object. +spec+ is a ConnectionSpecification
      # object which describes database connection information (e.g. adapter,
      # host name, username, password, etc), as well as the maximum size for
      # this ConnectionPool.
      #
      # The default ConnectionPool maximum size is 5.
      def initialize(spec)
        super()

        @spec = spec

        # The cache of reserved connections mapped to threads
        @reserved_connections = {}

        @queue = new_cond
        # 'wait_timeout', the backward-compatible key, conflicts with spec key 
        # used by mysql2 for something entirely different, checkout_timeout
        # preferred to avoid conflict and allow independent values. 
        @timeout = spec.config[:checkout_timeout] || spec.config[:wait_timeout] || 5

        # default max pool size to 5
        @size = (spec.config[:pool] && spec.config[:pool].to_i) || 5

        @connections         = []
        @automatic_reconnect = true
      end

      # Retrieve the connection associated with the current thread, or call
      # #checkout to obtain one if necessary.
      #
      # #connection can be called any number of times; the connection is
      # held in a hash keyed by the thread id.
      def connection
        synchronize do
          @reserved_connections[current_connection_id] ||= checkout
        end
      end

      # Is there an open connection that is being used for the current thread?
      def active_connection?
        synchronize do
          @reserved_connections.fetch(current_connection_id) {
            return false
          }.in_use?
        end
      end

      # Signal that the thread is finished with the current connection.
      # #release_connection releases the connection-thread association
      # and returns the connection to the pool.
      def release_connection(with_id = current_connection_id)
        conn = synchronize { @reserved_connections.delete(with_id) }
        checkin conn if conn
      end

      # If a connection already exists yield it to the block. If no connection
      # exists checkout a connection, yield it to the block, and checkin the
      # connection when finished.
      def with_connection
        connection_id = current_connection_id
        fresh_connection = true unless active_connection?
        yield connection
      ensure
        release_connection(connection_id) if fresh_connection
      end

      # Returns true if a connection has already been opened.
      def connected?
        synchronize { @connections.any? }
      end

      # Disconnects all connections in the pool, and clears the pool.
      def disconnect!
        synchronize do
          @reserved_connections = {}
          @connections.each do |conn|
            checkin conn
            conn.disconnect!
          end
          @connections = []
        end
      end

      # Clears the cache which maps classes.
      def clear_reloadable_connections!
        synchronize do
          @reserved_connections = {}
          @connections.each do |conn|
            checkin conn
            conn.disconnect! if conn.requires_reloading?
          end
          @connections.delete_if do |conn|
            conn.requires_reloading?
          end
        end
      end

      # Verify active connections and remove and disconnect connections
      # associated with stale threads.
      def verify_active_connections! #:nodoc:
        synchronize do
          clear_stale_cached_connections!
          @connections.each do |connection|
            connection.verify!
          end
        end
      end

      def columns
        with_connection do |c|
          c.schema_cache.columns
        end
      end
      deprecate :columns

      def columns_hash
        with_connection do |c|
          c.schema_cache.columns_hash
        end
      end
      deprecate :columns_hash

      def primary_keys
        with_connection do |c|
          c.schema_cache.primary_keys
        end
      end
      deprecate :primary_keys

      def clear_cache!
        with_connection do |c|
          c.schema_cache.clear!
        end
      end
      deprecate :clear_cache!

      # Return any checked-out connections back to the pool by threads that
      # are no longer alive.
      def clear_stale_cached_connections!
        keys = @reserved_connections.keys - Thread.list.find_all { |t|
          t.alive?
        }.map { |thread| thread.object_id }
        keys.each do |key|
          conn = @reserved_connections[key]
          ActiveSupport::Deprecation.warn(<<-eowarn) if conn.in_use?
Database connections will not be closed automatically, please close your
database connection at the end of the thread by calling `close` on your
connection.  For example: ActiveRecord::Base.connection.close
          eowarn
          checkin conn
          @reserved_connections.delete(key)
        end
      end

      # Check-out a database connection from the pool, indicating that you want
      # to use it. You should call #checkin when you no longer need this.
      #
      # This is done by either returning an existing connection, or by creating
      # a new connection. If the maximum number of connections for this pool has
      # already been reached, but the pool is empty (i.e. they're all being used),
      # then this method will wait until a thread has checked in a connection.
      # The wait time is bounded however: if no connection can be checked out
      # within the timeout specified for this pool, then a ConnectionTimeoutError
      # exception will be raised.
      #
      # Returns: an AbstractAdapter object.
      #
      # Raises:
      # - ConnectionTimeoutError: no connection can be obtained from the pool
      #   within the timeout period.
      def checkout
        synchronize do
          waited_time = 0

          loop do
            conn = @connections.find { |c| c.lease }

            unless conn
              if @connections.size < @size
                conn = checkout_new_connection
                conn.lease
              end
            end

            if conn
              checkout_and_verify conn
              return conn
            end

            if waited_time >= @timeout
              raise ConnectionTimeoutError, "could not obtain a database connection#{" within #{@timeout} seconds" if @timeout} (waited #{waited_time} seconds). The max pool size is currently #{@size}; consider increasing it."
            end

            # Sometimes our wait can end because a connection is available,
            # but another thread can snatch it up first. If timeout hasn't
            # passed but no connection is avail, looks like that happened --
            # loop and wait again, for the time remaining on our timeout. 
            before_wait = Time.now
            @queue.wait( [@timeout - waited_time, 0].max )
            waited_time += (Time.now - before_wait)

            # Will go away in Rails 4, when we don't clean up
            # after leaked connections automatically anymore. Right now, clean
            # up after we've returned from a 'wait' if it looks like it's
            # needed, then loop and try again. 
            if(active_connections.size >= @connections.size)
              clear_stale_cached_connections!
            end
          end
        end
      end

      # Check-in a database connection back into the pool, indicating that you
      # no longer need this connection.
      #
      # +conn+: an AbstractAdapter object, which was obtained by earlier by
      # calling +checkout+ on this pool.
      def checkin(conn)
        synchronize do
          conn.run_callbacks :checkin do
            conn.expire
            @queue.signal
          end

          release conn
        end
      end

      private

      def release(conn)
        synchronize do
          thread_id = nil

          if @reserved_connections[current_connection_id] == conn
            thread_id = current_connection_id
          else
            thread_id = @reserved_connections.keys.find { |k|
              @reserved_connections[k] == conn
            }
          end

          @reserved_connections.delete thread_id if thread_id
        end
      end

      def new_connection
        ActiveRecord::Base.send(spec.adapter_method, spec.config)
      end

      def current_connection_id #:nodoc:
        ActiveRecord::Base.connection_id ||= Thread.current.object_id
      end

      def checkout_new_connection
        raise ConnectionNotEstablished unless @automatic_reconnect

        c = new_connection
        c.pool = self
        @connections << c
        c
      end

      def checkout_and_verify(c)
        c.run_callbacks :checkout do
          c.verify!
        end
        c
      end

      def active_connections
        @connections.find_all { |c| c.in_use? }
      end
    end

    # ConnectionHandler is a collection of ConnectionPool objects. It is used
    # for keeping separate connection pools for Active Record models that connect
    # to different databases.
    #
    # For example, suppose that you have 5 models, with the following hierarchy:
    #
    #  |
    #  +-- Book
    #  |    |
    #  |    +-- ScaryBook
    #  |    +-- GoodBook
    #  +-- Author
    #  +-- BankAccount
    #
    # Suppose that Book is to connect to a separate database (i.e. one other
    # than the default database). Then Book, ScaryBook and GoodBook will all use
    # the same connection pool. Likewise, Author and BankAccount will use the
    # same connection pool. However, the connection pool used by Author/BankAccount
    # is not the same as the one used by Book/ScaryBook/GoodBook.
    #
    # Normally there is only a single ConnectionHandler instance, accessible via
    # ActiveRecord::Base.connection_handler. Active Record models use this to
    # determine that connection pool that they should use.
    class ConnectionHandler
      attr_reader :connection_pools

      def initialize(pools = {})
        @connection_pools = pools
        @class_to_pool    = {}
      end

      def establish_connection(name, spec)
        @connection_pools[spec] ||= ConnectionAdapters::ConnectionPool.new(spec)
        @class_to_pool[name] = @connection_pools[spec]
      end

      # Returns true if there are any active connections among the connection
      # pools that the ConnectionHandler is managing.
      def active_connections?
        connection_pools.values.any? { |pool| pool.active_connection? }
      end

      # Returns any connections in use by the current thread back to the pool.
      def clear_active_connections!
        @connection_pools.each_value {|pool| pool.release_connection }
      end

      # Clears the cache which maps classes.
      def clear_reloadable_connections!
        @connection_pools.each_value {|pool| pool.clear_reloadable_connections! }
      end

      def clear_all_connections!
        @connection_pools.each_value {|pool| pool.disconnect! }
      end

      # Verify active connections.
      def verify_active_connections! #:nodoc:
        @connection_pools.each_value {|pool| pool.verify_active_connections! }
      end

      # Locate the connection of the nearest super class. This can be an
      # active or defined connection: if it is the latter, it will be
      # opened and set as the active connection for the class it was defined
      # for (not necessarily the current class).
      def retrieve_connection(klass) #:nodoc:
        pool = retrieve_connection_pool(klass)
        (pool && pool.connection) or raise ConnectionNotEstablished
      end

      # Returns true if a connection that's accessible to this class has
      # already been opened.
      def connected?(klass)
        conn = retrieve_connection_pool(klass)
        conn && conn.connected?
      end

      # Remove the connection for this class. This will close the active
      # connection and the defined connection (if they exist). The result
      # can be used as an argument for establish_connection, for easily
      # re-establishing the connection.
      def remove_connection(klass)
        pool = @class_to_pool.delete(klass.name)
        return nil unless pool

        @connection_pools.delete pool.spec
        pool.automatic_reconnect = false
        pool.disconnect!
        pool.spec.config
      end

      def retrieve_connection_pool(klass)
        pool = @class_to_pool[klass.name]
        return pool if pool
        return nil if ActiveRecord::Base == klass
        retrieve_connection_pool klass.superclass
      end
    end

    class ConnectionManagement
      class Proxy # :nodoc:
        attr_reader :body, :testing

        def initialize(body, testing = false)
          @body    = body
          @testing = testing
        end

        def method_missing(method_sym, *arguments, &block)
          @body.send(method_sym, *arguments, &block)
        end

        def respond_to?(method_sym, include_private = false)
          super || @body.respond_to?(method_sym)
        end

        def each(&block)
          body.each(&block)
        end

        def close
          body.close if body.respond_to?(:close)

          # Don't return connection (and perform implicit rollback) if
          # this request is a part of integration test
          ActiveRecord::Base.clear_active_connections! unless testing
        end
      end

      def initialize(app)
        @app = app
      end

      def call(env)
        testing = env.key?('rack.test')

        status, headers, body = @app.call(env)

        [status, headers, Proxy.new(body, testing)]
      rescue
        ActiveRecord::Base.clear_active_connections! unless testing
        raise
      end
    end
  end
end
require 'uri'

module ActiveRecord
  class Base
    class ConnectionSpecification #:nodoc:
      attr_reader :config, :adapter_method
      def initialize (config, adapter_method)
        @config, @adapter_method = config, adapter_method
      end

      ##
      # Builds a ConnectionSpecification from user input
      class Resolver # :nodoc:
        attr_reader :config, :klass, :configurations

        def initialize(config, configurations)
          @config         = config
          @configurations = configurations
        end

        def spec
          case config
          when nil
            raise AdapterNotSpecified unless defined?(Rails.env)
            resolve_string_connection Rails.env
          when Symbol, String
            resolve_string_connection config.to_s
          when Hash
            resolve_hash_connection config
          end
        end

        private
        def resolve_string_connection(spec) # :nodoc:
          hash = configurations.fetch(spec) do |k|
            connection_url_to_hash(k)
          end

          raise(AdapterNotSpecified, "#{spec} database is not configured") unless hash

          resolve_hash_connection hash
        end

        def resolve_hash_connection(spec) # :nodoc:
          spec = spec.symbolize_keys

          raise(AdapterNotSpecified, "database configuration does not specify adapter") unless spec.key?(:adapter)

          begin
            require "active_record/connection_adapters/#{spec[:adapter]}_adapter"
          rescue LoadError => e
            raise LoadError, "Please install the #{spec[:adapter]} adapter: `gem install activerecord-#{spec[:adapter]}-adapter` (#{e.message})", e.backtrace
          end

          adapter_method = "#{spec[:adapter]}_connection"

          ConnectionSpecification.new(spec, adapter_method)
        end

        def connection_url_to_hash(url) # :nodoc:
          config = URI.parse url
          adapter = config.scheme
          adapter = "postgresql" if adapter == "postgres"
          spec = { :adapter  => adapter,
                   :username => config.user,
                   :password => config.password,
                   :port     => config.port,
                   :database => config.path.sub(%r{^/},""),
                   :host     => config.host }
          spec.reject!{ |_,value| value.blank? }
          spec.map { |key,value| spec[key] = URI.unescape(value) if value.is_a?(String) }
          if config.query
            options = Hash[config.query.split("&").map{ |pair| pair.split("=") }].symbolize_keys
            spec.merge!(options)
          end
          spec
        end
      end
    end

    ##
    # :singleton-method:
    # The connection handler
    class_attribute :connection_handler, :instance_writer => false
    self.connection_handler = ConnectionAdapters::ConnectionHandler.new

    # Returns the connection currently associated with the class. This can
    # also be used to "borrow" the connection to do database work that isn't
    # easily done without going straight to SQL.
    def connection
      self.class.connection
    end

    # Establishes the connection to the database. Accepts a hash as input where
    # the <tt>:adapter</tt> key must be specified with the name of a database adapter (in lower-case)
    # example for regular databases (MySQL, Postgresql, etc):
    #
    #   ActiveRecord::Base.establish_connection(
    #     :adapter  => "mysql",
    #     :host     => "localhost",
    #     :username => "myuser",
    #     :password => "mypass",
    #     :database => "somedatabase"
    #   )
    #
    # Example for SQLite database:
    #
    #   ActiveRecord::Base.establish_connection(
    #     :adapter => "sqlite",
    #     :database  => "path/to/dbfile"
    #   )
    #
    # Also accepts keys as strings (for parsing from YAML for example):
    #
    #   ActiveRecord::Base.establish_connection(
    #     "adapter" => "sqlite",
    #     "database"  => "path/to/dbfile"
    #   )
    #
    # Or a URL:
    #
    #   ActiveRecord::Base.establish_connection(
    #     "postgres://myuser:mypass@localhost/somedatabase"
    #   )
    #
    # The exceptions AdapterNotSpecified, AdapterNotFound and ArgumentError
    # may be returned on an error.
    def self.establish_connection(spec = ENV["DATABASE_URL"])
      resolver = ConnectionSpecification::Resolver.new spec, configurations
      spec = resolver.spec

      unless respond_to?(spec.adapter_method)
        raise AdapterNotFound, "database configuration specifies nonexistent #{spec.config[:adapter]} adapter"
      end

      remove_connection
      connection_handler.establish_connection name, spec
    end

    class << self
      # Returns the connection currently associated with the class. This can
      # also be used to "borrow" the connection to do database work unrelated
      # to any of the specific Active Records.
      def connection
        retrieve_connection
      end

      def connection_id
        Thread.current['ActiveRecord::Base.connection_id']
      end

      def connection_id=(connection_id)
        Thread.current['ActiveRecord::Base.connection_id'] = connection_id
      end

      # Returns the configuration of the associated connection as a hash:
      #
      #  ActiveRecord::Base.connection_config
      #  # => {:pool=>5, :timeout=>5000, :database=>"db/development.sqlite3", :adapter=>"sqlite3"}
      #
      # Please use only for reading.
      def connection_config
        connection_pool.spec.config
      end

      def connection_pool
        connection_handler.retrieve_connection_pool(self) or raise ConnectionNotEstablished
      end

      def retrieve_connection
        connection_handler.retrieve_connection(self)
      end

      # Returns true if Active Record is connected.
      def connected?
        connection_handler.connected?(self)
      end

      def remove_connection(klass = self)
        connection_handler.remove_connection(klass)
      end

      def clear_active_connections!
        connection_handler.clear_active_connections!
      end

      delegate :clear_reloadable_connections!,
        :clear_all_connections!,:verify_active_connections!, :to => :connection_handler
    end
  end
end
module ActiveRecord
  module ConnectionAdapters # :nodoc:
    module DatabaseLimits

      # Returns the maximum length of a table alias.
      def table_alias_length
        255
      end

      # Returns the maximum length of a column name.
      def column_name_length
        64
      end

      # Returns the maximum length of a table name.
      def table_name_length
        64
      end

      # Returns the maximum length of an index name.
      def index_name_length
        64
      end

      # Returns the maximum number of columns per table.
      def columns_per_table
        1024
      end

      # Returns the maximum number of indexes per table.
      def indexes_per_table
        16
      end

      # Returns the maximum number of columns in a multicolumn index.
      def columns_per_multicolumn_index
        16
      end

      # Returns the maximum number of elements in an IN (x,y,z) clause.
      # nil means no limit.
      def in_clause_length
        nil
      end

      # Returns the maximum length of an SQL query.
      def sql_query_length
        1048575
      end

      # Returns maximum number of joins in a single query.
      def joins_per_query
        256
      end

    end
  end
end
module ActiveRecord
  module ConnectionAdapters # :nodoc:
    module DatabaseStatements
      # Converts an arel AST to SQL
      def to_sql(arel, binds = [])
        if arel.respond_to?(:ast)
          visitor.accept(arel.ast) do
            quote(*binds.shift.reverse)
          end
        else
          arel
        end
      end

      # Returns an array of record hashes with the column names as keys and
      # column values as values.
      def select_all(arel, name = nil, binds = [])
        select(to_sql(arel, binds), name, binds)
      end

      # Returns a record hash with the column names as keys and column values
      # as values.
      def select_one(arel, name = nil)
        result = select_all(arel, name)
        result.first if result
      end

      # Returns a single value from a record
      def select_value(arel, name = nil)
        if result = select_one(arel, name)
          result.values.first
        end
      end

      # Returns an array of the values of the first column in a select:
      #   select_values("SELECT id FROM companies LIMIT 3") => [1,2,3]
      def select_values(arel, name = nil)
        result = select_rows(to_sql(arel, []), name)
        result.map { |v| v[0] }
      end

      # Returns an array of arrays containing the field values.
      # Order is the same as that returned by +columns+.
      def select_rows(sql, name = nil)
      end
      undef_method :select_rows

      # Executes the SQL statement in the context of this connection.
      def execute(sql, name = nil)
      end
      undef_method :execute

      # Executes +sql+ statement in the context of this connection using
      # +binds+ as the bind substitutes. +name+ is logged along with
      # the executed +sql+ statement.
      def exec_query(sql, name = 'SQL', binds = [])
      end

      # Executes insert +sql+ statement in the context of this connection using
      # +binds+ as the bind substitutes. +name+ is the logged along with
      # the executed +sql+ statement.
      def exec_insert(sql, name, binds)
        exec_query(sql, name, binds)
      end

      # Executes delete +sql+ statement in the context of this connection using
      # +binds+ as the bind substitutes. +name+ is the logged along with
      # the executed +sql+ statement.
      def exec_delete(sql, name, binds)
        exec_query(sql, name, binds)
      end

      # Executes update +sql+ statement in the context of this connection using
      # +binds+ as the bind substitutes. +name+ is the logged along with
      # the executed +sql+ statement.
      def exec_update(sql, name, binds)
        exec_query(sql, name, binds)
      end

      # Returns the last auto-generated ID from the affected table.
      #
      # +id_value+ will be returned unless the value is nil, in
      # which case the database will attempt to calculate the last inserted
      # id and return that value.
      #
      # If the next id was calculated in advance (as in Oracle), it should be
      # passed in as +id_value+.
      def insert(arel, name = nil, pk = nil, id_value = nil, sequence_name = nil, binds = [])
        sql, binds = sql_for_insert(to_sql(arel, binds), pk, id_value, sequence_name, binds)
        value      = exec_insert(sql, name, binds)
        id_value || last_inserted_id(value)
      end

      # Executes the update statement and returns the number of rows affected.
      def update(arel, name = nil, binds = [])
        exec_update(to_sql(arel, binds), name, binds)
      end

      # Executes the delete statement and returns the number of rows affected.
      def delete(arel, name = nil, binds = [])
        exec_delete(to_sql(arel, binds), name, binds)
      end

      # Checks whether there is currently no transaction active. This is done
      # by querying the database driver, and does not use the transaction
      # house-keeping information recorded by #increment_open_transactions and
      # friends.
      #
      # Returns true if there is no transaction active, false if there is a
      # transaction active, and nil if this information is unknown.
      #
      # Not all adapters supports transaction state introspection. Currently,
      # only the PostgreSQL adapter supports this.
      def outside_transaction?
        nil
      end

      # Returns +true+ when the connection adapter supports prepared statement
      # caching, otherwise returns +false+
      def supports_statement_cache?
        false
      end

      # Runs the given block in a database transaction, and returns the result
      # of the block.
      #
      # == Nested transactions support
      #
      # Most databases don't support true nested transactions. At the time of
      # writing, the only database that supports true nested transactions that
      # we're aware of, is MS-SQL.
      #
      # In order to get around this problem, #transaction will emulate the effect
      # of nested transactions, by using savepoints:
      # http://dev.mysql.com/doc/refman/5.0/en/savepoint.html
      # Savepoints are supported by MySQL and PostgreSQL, but not SQLite3.
      #
      # It is safe to call this method if a database transaction is already open,
      # i.e. if #transaction is called within another #transaction block. In case
      # of a nested call, #transaction will behave as follows:
      #
      # - The block will be run without doing anything. All database statements
      #   that happen within the block are effectively appended to the already
      #   open database transaction.
      # - However, if +:requires_new+ is set, the block will be wrapped in a
      #   database savepoint acting as a sub-transaction.
      #
      # === Caveats
      #
      # MySQL doesn't support DDL transactions. If you perform a DDL operation,
      # then any created savepoints will be automatically released. For example,
      # if you've created a savepoint, then you execute a CREATE TABLE statement,
      # then the savepoint that was created will be automatically released.
      #
      # This means that, on MySQL, you shouldn't execute DDL operations inside
      # a #transaction call that you know might create a savepoint. Otherwise,
      # #transaction will raise exceptions when it tries to release the
      # already-automatically-released savepoints:
      #
      #   Model.connection.transaction do  # BEGIN
      #     Model.connection.transaction(:requires_new => true) do  # CREATE SAVEPOINT active_record_1
      #       Model.connection.create_table(...)
      #       # active_record_1 now automatically released
      #     end  # RELEASE SAVEPOINT active_record_1  <--- BOOM! database error!
      #   end
      def transaction(options = {})
        options.assert_valid_keys :requires_new, :joinable

        last_transaction_joinable = defined?(@transaction_joinable) ? @transaction_joinable : nil
        if options.has_key?(:joinable)
          @transaction_joinable = options[:joinable]
        else
          @transaction_joinable = true
        end
        requires_new = options[:requires_new] || !last_transaction_joinable

        transaction_open = false
        @_current_transaction_records ||= []

        begin
          if block_given?
            if requires_new || open_transactions == 0
              if open_transactions == 0
                begin_db_transaction
              elsif requires_new
                create_savepoint
              end
              increment_open_transactions
              transaction_open = true
              @_current_transaction_records.push([])
            end
            yield
          end
        rescue Exception => database_transaction_rollback
          if transaction_open && !outside_transaction?
            transaction_open = false
            decrement_open_transactions
            if open_transactions == 0
              rollback_db_transaction
              rollback_transaction_records(true)
            else
              rollback_to_savepoint
              rollback_transaction_records(false)
            end
          end
          raise unless database_transaction_rollback.is_a?(ActiveRecord::Rollback)
        end
      ensure
        @transaction_joinable = last_transaction_joinable

        if outside_transaction?
          @open_transactions = 0
        elsif transaction_open
          decrement_open_transactions
          begin
            if open_transactions == 0
              commit_db_transaction
              commit_transaction_records
            else
              release_savepoint
              save_point_records = @_current_transaction_records.pop
              unless save_point_records.blank?
                @_current_transaction_records.push([]) if @_current_transaction_records.empty?
                @_current_transaction_records.last.concat(save_point_records)
              end
            end
          rescue Exception => database_transaction_rollback
            if open_transactions == 0
              rollback_db_transaction
              rollback_transaction_records(true)
            else
              rollback_to_savepoint
              rollback_transaction_records(false)
            end
            raise
          end
        end
      end

      # Register a record with the current transaction so that its after_commit and after_rollback callbacks
      # can be called.
      def add_transaction_record(record)
        last_batch = @_current_transaction_records.last
        last_batch << record if last_batch
      end

      # Begins the transaction (and turns off auto-committing).
      def begin_db_transaction()    end

      # Commits the transaction (and turns on auto-committing).
      def commit_db_transaction()   end

      # Rolls back the transaction (and turns on auto-committing). Must be
      # done if the transaction block raises an exception or returns false.
      def rollback_db_transaction() end

      def default_sequence_name(table, column)
        nil
      end

      # Set the sequence to the max value of the table's column.
      def reset_sequence!(table, column, sequence = nil)
        # Do nothing by default. Implement for PostgreSQL, Oracle, ...
      end

      # Inserts the given fixture into the table. Overridden in adapters that require
      # something beyond a simple insert (eg. Oracle).
      def insert_fixture(fixture, table_name)
        columns = Hash[columns(table_name).map { |c| [c.name, c] }]

        key_list   = []
        value_list = fixture.map do |name, value|
          key_list << quote_column_name(name)
          quote(value, columns[name])
        end

        execute "INSERT INTO #{quote_table_name(table_name)} (#{key_list.join(', ')}) VALUES (#{value_list.join(', ')})", 'Fixture Insert'
      end

      def empty_insert_statement_value
        "VALUES(DEFAULT)"
      end

      def case_sensitive_equality_operator
        "="
      end

      def limited_update_conditions(where_sql, quoted_table_name, quoted_primary_key)
        "WHERE #{quoted_primary_key} IN (SELECT #{quoted_primary_key} FROM #{quoted_table_name} #{where_sql})"
      end

      # Sanitizes the given LIMIT parameter in order to prevent SQL injection.
      #
      # The +limit+ may be anything that can evaluate to a string via #to_s. It
      # should look like an integer, or a comma-delimited list of integers, or
      # an Arel SQL literal.
      #
      # Returns Integer and Arel::Nodes::SqlLiteral limits as is.
      # Returns the sanitized limit parameter, either as an integer, or as a
      # string which contains a comma-delimited list of integers.
      def sanitize_limit(limit)
        if limit.is_a?(Integer) || limit.is_a?(Arel::Nodes::SqlLiteral)
          limit
        elsif limit.to_s =~ /,/
          Arel.sql limit.to_s.split(',').map{ |i| Integer(i) }.join(',')
        else
          Integer(limit)
        end
      end

      # The default strategy for an UPDATE with joins is to use a subquery. This doesn't work
      # on mysql (even when aliasing the tables), but mysql allows using JOIN directly in
      # an UPDATE statement, so in the mysql adapters we redefine this to do that.
      def join_to_update(update, select) #:nodoc:
        subselect = select.clone
        subselect.projections = [update.key]

        update.where update.key.in(subselect)
      end

      protected
        # Returns an array of record hashes with the column names as keys and
        # column values as values.
        def select(sql, name = nil, binds = [])
        end
        undef_method :select

        # Returns the last auto-generated ID from the affected table.
        def insert_sql(sql, name = nil, pk = nil, id_value = nil, sequence_name = nil)
          execute(sql, name)
          id_value
        end

        # Executes the update statement and returns the number of rows affected.
        def update_sql(sql, name = nil)
          execute(sql, name)
        end

        # Executes the delete statement and returns the number of rows affected.
        def delete_sql(sql, name = nil)
          update_sql(sql, name)
        end

        # Send a rollback message to all records after they have been rolled back. If rollback
        # is false, only rollback records since the last save point.
        def rollback_transaction_records(rollback)
          if rollback
            records = @_current_transaction_records.flatten
            @_current_transaction_records.clear
          else
            records = @_current_transaction_records.pop
          end

          unless records.blank?
            records.uniq.each do |record|
              begin
                record.rolledback!(rollback)
              rescue Exception => e
                record.logger.error(e) if record.respond_to?(:logger) && record.logger
              end
            end
          end
        end

        # Send a commit message to all records after they have been committed.
        def commit_transaction_records
          records = @_current_transaction_records.flatten
          @_current_transaction_records.clear
          unless records.blank?
            records.uniq.each do |record|
              begin
                record.committed!
              rescue Exception => e
                record.logger.error(e) if record.respond_to?(:logger) && record.logger
              end
            end
          end
        end

      def sql_for_insert(sql, pk, id_value, sequence_name, binds)
        [sql, binds]
      end

      def last_inserted_id(result)
        row = result.rows.first
        row && row.first
      end
    end
  end
end
module ActiveRecord
  module ConnectionAdapters # :nodoc:
    module QueryCache
      class << self
        def included(base)
          dirties_query_cache base, :insert, :update, :delete
        end

        def dirties_query_cache(base, *method_names)
          method_names.each do |method_name|
            base.class_eval <<-end_code, __FILE__, __LINE__ + 1
              def #{method_name}(*)                         # def update_with_query_dirty(*args)
                clear_query_cache if @query_cache_enabled   #   clear_query_cache if @query_cache_enabled
                super                                       #   update_without_query_dirty(*args)
              end                                           # end
            end_code
          end
        end
      end

      attr_reader :query_cache, :query_cache_enabled

      # Enable the query cache within the block.
      def cache
        old, @query_cache_enabled = @query_cache_enabled, true
        yield
      ensure
        clear_query_cache
        @query_cache_enabled = old
      end

      def enable_query_cache!
        @query_cache_enabled = true
      end

      def disable_query_cache!
        @query_cache_enabled = false
      end

      # Disable the query cache within the block.
      def uncached
        old, @query_cache_enabled = @query_cache_enabled, false
        yield
      ensure
        @query_cache_enabled = old
      end

      # Clears the query cache.
      #
      # One reason you may wish to call this method explicitly is between queries
      # that ask the database to randomize results. Otherwise the cache would see
      # the same SQL query and repeatedly return the same result each time, silently
      # undermining the randomness you were expecting.
      def clear_query_cache
        @query_cache.clear
      end

      def select_all(arel, name = nil, binds = [])
        if @query_cache_enabled && !locked?(arel)
          sql = to_sql(arel, binds)
          cache_sql(sql, binds) { super(sql, name, binds) }
        else
          super
        end
      end

      private
        def cache_sql(sql, binds)
          result =
            if @query_cache[sql].key?(binds)
              ActiveSupport::Notifications.instrument("sql.active_record",
                :sql => sql, :binds => binds, :name => "CACHE", :connection_id => object_id)
              @query_cache[sql][binds]
            else
              @query_cache[sql][binds] = yield
            end

          result.collect { |row| row.dup }
        end

        def locked?(arel)
          if arel.respond_to?(:locked)
            arel.locked
          else
            false
          end
        end
    end
  end
end
require 'active_support/core_ext/big_decimal/conversions'

module ActiveRecord
  module ConnectionAdapters # :nodoc:
    module Quoting
      # Quotes the column value to help prevent
      # {SQL injection attacks}[http://en.wikipedia.org/wiki/SQL_injection].
      def quote(value, column = nil)
        # records are quoted as their primary key
        return value.quoted_id if value.respond_to?(:quoted_id)

        case value
        when String, ActiveSupport::Multibyte::Chars
          value = value.to_s
          return "'#{quote_string(value)}'" unless column

          case column.type
          when :binary then "'#{quote_string(column.string_to_binary(value))}'"
          when :integer then value.to_i.to_s
          when :float then value.to_f.to_s
          else
            "'#{quote_string(value)}'"
          end

        when true, false
          if column && column.type == :integer
            value ? '1' : '0'
          elsif column && [:text, :string, :binary].include?(column.type)
            value ? "'1'" : "'0'"
          else
            value ? quoted_true : quoted_false
          end
          # BigDecimals need to be put in a non-normalized form and quoted.
        when nil        then "NULL"
        when Numeric, ActiveSupport::Duration
          value = BigDecimal === value ? value.to_s('F') : value.to_s
          if column && ![:integer, :float, :decimal].include?(column.type)
            value = "'#{value}'"
          end
          value
        when Date, Time then "'#{quoted_date(value)}'"
        when Symbol     then "'#{quote_string(value.to_s)}'"
        else
          "'#{quote_string(YAML.dump(value))}'"
        end
      end

      # Cast a +value+ to a type that the database understands. For example,
      # SQLite does not understand dates, so this method will convert a Date
      # to a String.
      def type_cast(value, column)
        return value.id if value.respond_to?(:quoted_id)

        case value
        when String, ActiveSupport::Multibyte::Chars
          value = value.to_s
          return value unless column

          case column.type
          when :binary then value
          when :integer then value.to_i
          when :float then value.to_f
          else
            value
          end

        when true, false
          if column && column.type == :integer
            value ? 1 : 0
          else
            value ? 't' : 'f'
          end
          # BigDecimals need to be put in a non-normalized form and quoted.
        when nil        then nil
        when BigDecimal then value.to_s('F')
        when Numeric    then value
        when Date, Time then quoted_date(value)
        when Symbol     then value.to_s
        else
          YAML.dump(value)
        end
      end

      # Quotes a string, escaping any ' (single quote) and \ (backslash)
      # characters.
      def quote_string(s)
        s.gsub(/\\/, '\&\&').gsub(/'/, "''") # ' (for ruby-mode)
      end

      # Quotes the column name. Defaults to no quoting.
      def quote_column_name(column_name)
        column_name
      end

      # Quotes the table name. Defaults to column name quoting.
      def quote_table_name(table_name)
        quote_column_name(table_name)
      end

      def quoted_true
        "'t'"
      end

      def quoted_false
        "'f'"
      end

      def quoted_date(value)
        if value.acts_like?(:time)
          zone_conversion_method = ActiveRecord::Base.default_timezone == :utc ? :getutc : :getlocal

          if value.respond_to?(zone_conversion_method)
            value = value.send(zone_conversion_method)
          end
        end

        value.to_s(:db)
      end
    end
  end
end
require 'active_support/core_ext/object/blank'
require 'date'
require 'set'
require 'bigdecimal'
require 'bigdecimal/util'

module ActiveRecord
  module ConnectionAdapters #:nodoc:
    class IndexDefinition < Struct.new(:table, :name, :unique, :columns, :lengths, :orders) #:nodoc:
    end

    # Abstract representation of a column definition. Instances of this type
    # are typically created by methods in TableDefinition, and added to the
    # +columns+ attribute of said TableDefinition object, in order to be used
    # for generating a number of table creation or table changing SQL statements.
    class ColumnDefinition < Struct.new(:base, :name, :type, :limit, :precision, :scale, :default, :null) #:nodoc:

      def string_to_binary(value)
        value
      end

      def sql_type
        base.type_to_sql(type.to_sym, limit, precision, scale) rescue type
      end

      def to_sql
        column_sql = "#{base.quote_column_name(name)} #{sql_type}"
        column_options = {}
        column_options[:null] = null unless null.nil?
        column_options[:default] = default unless default.nil?
        add_column_options!(column_sql, column_options) unless type.to_sym == :primary_key
        column_sql
      end

      private

        def add_column_options!(sql, options)
          base.add_column_options!(sql, options.merge(:column => self))
        end
    end

    # Represents the schema of an SQL table in an abstract way. This class
    # provides methods for manipulating the schema representation.
    #
    # Inside migration files, the +t+ object in +create_table+ and
    # +change_table+ is actually of this type:
    #
    #   class SomeMigration < ActiveRecord::Migration
    #     def up
    #       create_table :foo do |t|
    #         puts t.class  # => "ActiveRecord::ConnectionAdapters::TableDefinition"
    #       end
    #     end
    #
    #     def down
    #       ...
    #     end
    #   end
    #
    # The table definitions
    # The Columns are stored as a ColumnDefinition in the +columns+ attribute.
    class TableDefinition
      # An array of ColumnDefinition objects, representing the column changes
      # that have been defined.
      attr_accessor :columns

      def initialize(base)
        @columns = []
        @columns_hash = {}
        @base = base
      end

      def xml(*args)
        raise NotImplementedError unless %w{
          sqlite mysql mysql2
        }.include? @base.adapter_name.downcase

        options = args.extract_options!
        column(args[0], :text, options)
      end

      # Appends a primary key definition to the table definition.
      # Can be called multiple times, but this is probably not a good idea.
      def primary_key(name)
        column(name, :primary_key)
      end

      # Returns a ColumnDefinition for the column with name +name+.
      def [](name)
        @columns_hash[name.to_s]
      end

      # Instantiates a new column for the table.
      # The +type+ parameter is normally one of the migrations native types,
      # which is one of the following:
      # <tt>:primary_key</tt>, <tt>:string</tt>, <tt>:text</tt>,
      # <tt>:integer</tt>, <tt>:float</tt>, <tt>:decimal</tt>,
      # <tt>:datetime</tt>, <tt>:timestamp</tt>, <tt>:time</tt>,
      # <tt>:date</tt>, <tt>:binary</tt>, <tt>:boolean</tt>.
      #
      # You may use a type not in this list as long as it is supported by your
      # database (for example, "polygon" in MySQL), but this will not be database
      # agnostic and should usually be avoided.
      #
      # Available options are (none of these exists by default):
      # * <tt>:limit</tt> -
      #   Requests a maximum column length. This is number of characters for <tt>:string</tt> and
      #   <tt>:text</tt> columns and number of bytes for <tt>:binary</tt> and <tt>:integer</tt> columns.
      # * <tt>:default</tt> -
      #   The column's default value. Use nil for NULL.
      # * <tt>:null</tt> -
      #   Allows or disallows +NULL+ values in the column. This option could
      #   have been named <tt>:null_allowed</tt>.
      # * <tt>:precision</tt> -
      #   Specifies the precision for a <tt>:decimal</tt> column.
      # * <tt>:scale</tt> -
      #   Specifies the scale for a <tt>:decimal</tt> column.
      #
      # For clarity's sake: the precision is the number of significant digits,
      # while the scale is the number of digits that can be stored following
      # the decimal point. For example, the number 123.45 has a precision of 5
      # and a scale of 2. A decimal with a precision of 5 and a scale of 2 can
      # range from -999.99 to 999.99.
      #
      # Please be aware of different RDBMS implementations behavior with
      # <tt>:decimal</tt> columns:
      # * The SQL standard says the default scale should be 0, <tt>:scale</tt> <=
      #   <tt>:precision</tt>, and makes no comments about the requirements of
      #   <tt>:precision</tt>.
      # * MySQL: <tt>:precision</tt> [1..63], <tt>:scale</tt> [0..30].
      #   Default is (10,0).
      # * PostgreSQL: <tt>:precision</tt> [1..infinity],
      #   <tt>:scale</tt> [0..infinity]. No default.
      # * SQLite2: Any <tt>:precision</tt> and <tt>:scale</tt> may be used.
      #   Internal storage as strings. No default.
      # * SQLite3: No restrictions on <tt>:precision</tt> and <tt>:scale</tt>,
      #   but the maximum supported <tt>:precision</tt> is 16. No default.
      # * Oracle: <tt>:precision</tt> [1..38], <tt>:scale</tt> [-84..127].
      #   Default is (38,0).
      # * DB2: <tt>:precision</tt> [1..63], <tt>:scale</tt> [0..62].
      #   Default unknown.
      # * Firebird: <tt>:precision</tt> [1..18], <tt>:scale</tt> [0..18].
      #   Default (9,0). Internal types NUMERIC and DECIMAL have different
      #   storage rules, decimal being better.
      # * FrontBase?: <tt>:precision</tt> [1..38], <tt>:scale</tt> [0..38].
      #   Default (38,0). WARNING Max <tt>:precision</tt>/<tt>:scale</tt> for
      #   NUMERIC is 19, and DECIMAL is 38.
      # * SqlServer?: <tt>:precision</tt> [1..38], <tt>:scale</tt> [0..38].
      #   Default (38,0).
      # * Sybase: <tt>:precision</tt> [1..38], <tt>:scale</tt> [0..38].
      #   Default (38,0).
      # * OpenBase?: Documentation unclear. Claims storage in <tt>double</tt>.
      #
      # This method returns <tt>self</tt>.
      #
      # == Examples
      #  # Assuming +td+ is an instance of TableDefinition
      #  td.column(:granted, :boolean)
      #  # granted BOOLEAN
      #
      #  td.column(:picture, :binary, :limit => 2.megabytes)
      #  # => picture BLOB(2097152)
      #
      #  td.column(:sales_stage, :string, :limit => 20, :default => 'new', :null => false)
      #  # => sales_stage VARCHAR(20) DEFAULT 'new' NOT NULL
      #
      #  td.column(:bill_gates_money, :decimal, :precision => 15, :scale => 2)
      #  # => bill_gates_money DECIMAL(15,2)
      #
      #  td.column(:sensor_reading, :decimal, :precision => 30, :scale => 20)
      #  # => sensor_reading DECIMAL(30,20)
      #
      #  # While <tt>:scale</tt> defaults to zero on most databases, it
      #  # probably wouldn't hurt to include it.
      #  td.column(:huge_integer, :decimal, :precision => 30)
      #  # => huge_integer DECIMAL(30)
      #
      #  # Defines a column with a database-specific type.
      #  td.column(:foo, 'polygon')
      #  # => foo polygon
      #
      # == Short-hand examples
      #
      # Instead of calling +column+ directly, you can also work with the short-hand definitions for the default types.
      # They use the type as the method name instead of as a parameter and allow for multiple columns to be defined
      # in a single statement.
      #
      # What can be written like this with the regular calls to column:
      #
      #   create_table "products", :force => true do |t|
      #     t.column "shop_id",    :integer
      #     t.column "creator_id", :integer
      #     t.column "name",       :string,   :default => "Untitled"
      #     t.column "value",      :string,   :default => "Untitled"
      #     t.column "created_at", :datetime
      #     t.column "updated_at", :datetime
      #   end
      #
      # Can also be written as follows using the short-hand:
      #
      #   create_table :products do |t|
      #     t.integer :shop_id, :creator_id
      #     t.string  :name, :value, :default => "Untitled"
      #     t.timestamps
      #   end
      #
      # There's a short-hand method for each of the type values declared at the top. And then there's
      # TableDefinition#timestamps that'll add +created_at+ and +updated_at+ as datetimes.
      #
      # TableDefinition#references will add an appropriately-named _id column, plus a corresponding _type
      # column if the <tt>:polymorphic</tt> option is supplied. If <tt>:polymorphic</tt> is a hash of
      # options, these will be used when creating the <tt>_type</tt> column. So what can be written like this:
      #
      #   create_table :taggings do |t|
      #     t.integer :tag_id, :tagger_id, :taggable_id
      #     t.string  :tagger_type
      #     t.string  :taggable_type, :default => 'Photo'
      #   end
      #
      # Can also be written as follows using references:
      #
      #   create_table :taggings do |t|
      #     t.references :tag
      #     t.references :tagger, :polymorphic => true
      #     t.references :taggable, :polymorphic => { :default => 'Photo' }
      #   end
      def column(name, type, options = {})
        name = name.to_s
        type = type.to_sym

        column = self[name] || new_column_definition(@base, name, type)

        limit = options.fetch(:limit) do
          native[type][:limit] if native[type].is_a?(Hash)
        end

        column.limit     = limit
        column.precision = options[:precision]
        column.scale     = options[:scale]
        column.default   = options[:default]
        column.null      = options[:null]
        self
      end

      %w( string text integer float decimal datetime timestamp time date binary boolean ).each do |column_type|
        class_eval <<-EOV, __FILE__, __LINE__ + 1
          def #{column_type}(*args)                                   # def string(*args)
            options = args.extract_options!                           #   options = args.extract_options!
            column_names = args                                       #   column_names = args
            type = :'#{column_type}'                                  #   type = :string
            column_names.each { |name| column(name, type, options) }  #   column_names.each { |name| column(name, type, options) }
          end                                                         # end
        EOV
      end

      # Appends <tt>:datetime</tt> columns <tt>:created_at</tt> and
      # <tt>:updated_at</tt> to the table.
      def timestamps(*args)
        options = { :null => false }.merge(args.extract_options!)
        column(:created_at, :datetime, options)
        column(:updated_at, :datetime, options)
      end

      def references(*args)
        options = args.extract_options!
        polymorphic = options.delete(:polymorphic)
        args.each do |col|
          column("#{col}_id", :integer, options)
          column("#{col}_type", :string, polymorphic.is_a?(Hash) ? polymorphic : options) unless polymorphic.nil?
        end
      end
      alias :belongs_to :references

      # Returns a String whose contents are the column definitions
      # concatenated together. This string can then be prepended and appended to
      # to generate the final SQL to create the table.
      def to_sql
        @columns.map { |c| c.to_sql } * ', '
      end

      private
      def new_column_definition(base, name, type)
        definition = ColumnDefinition.new base, name, type
        @columns << definition
        @columns_hash[name] = definition
        definition
      end

      def native
        @base.native_database_types
      end
    end

    # Represents an SQL table in an abstract way for updating a table.
    # Also see TableDefinition and SchemaStatements#create_table
    #
    # Available transformations are:
    #
    #   change_table :table do |t|
    #     t.column
    #     t.index
    #     t.timestamps
    #     t.change
    #     t.change_default
    #     t.rename
    #     t.references
    #     t.belongs_to
    #     t.string
    #     t.text
    #     t.integer
    #     t.float
    #     t.decimal
    #     t.datetime
    #     t.timestamp
    #     t.time
    #     t.date
    #     t.binary
    #     t.boolean
    #     t.remove
    #     t.remove_references
    #     t.remove_belongs_to
    #     t.remove_index
    #     t.remove_timestamps
    #   end
    #
    class Table
      def initialize(table_name, base)
        @table_name = table_name
        @base = base
      end

      # Adds a new column to the named table.
      # See TableDefinition#column for details of the options you can use.
      # ===== Example
      # ====== Creating a simple column
      #  t.column(:name, :string)
      def column(column_name, type, options = {})
        @base.add_column(@table_name, column_name, type, options)
      end

      # Checks to see if a column exists. See SchemaStatements#column_exists?
      def column_exists?(column_name, type = nil, options = {})
        @base.column_exists?(@table_name, column_name, type, options)
      end

      # Adds a new index to the table. +column_name+ can be a single Symbol, or
      # an Array of Symbols. See SchemaStatements#add_index
      #
      # ===== Examples
      # ====== Creating a simple index
      #  t.index(:name)
      # ====== Creating a unique index
      #  t.index([:branch_id, :party_id], :unique => true)
      # ====== Creating a named index
      #  t.index([:branch_id, :party_id], :unique => true, :name => 'by_branch_party')
      def index(column_name, options = {})
        @base.add_index(@table_name, column_name, options)
      end

      # Checks to see if an index exists. See SchemaStatements#index_exists?
      def index_exists?(column_name, options = {})
        @base.index_exists?(@table_name, column_name, options)
      end

      # Adds timestamps (+created_at+ and +updated_at+) columns to the table. See SchemaStatements#add_timestamps
      # ===== Example
      #  t.timestamps
      def timestamps
        @base.add_timestamps(@table_name)
      end

      # Changes the column's definition according to the new options.
      # See TableDefinition#column for details of the options you can use.
      # ===== Examples
      #  t.change(:name, :string, :limit => 80)
      #  t.change(:description, :text)
      def change(column_name, type, options = {})
        @base.change_column(@table_name, column_name, type, options)
      end

      # Sets a new default value for a column. See SchemaStatements#change_column_default
      # ===== Examples
      #  t.change_default(:qualification, 'new')
      #  t.change_default(:authorized, 1)
      def change_default(column_name, default)
        @base.change_column_default(@table_name, column_name, default)
      end

      # Removes the column(s) from the table definition.
      # ===== Examples
      #  t.remove(:qualification)
      #  t.remove(:qualification, :experience)
      def remove(*column_names)
        @base.remove_column(@table_name, *column_names)
      end

      # Removes the given index from the table.
      #
      # ===== Examples
      # ====== Remove the index_table_name_on_column in the table_name table
      #   t.remove_index :column
      # ====== Remove the index named index_table_name_on_branch_id in the table_name table
      #   t.remove_index :column => :branch_id
      # ====== Remove the index named index_table_name_on_branch_id_and_party_id in the table_name table
      #   t.remove_index :column => [:branch_id, :party_id]
      # ====== Remove the index named by_branch_party in the table_name table
      #   t.remove_index :name => :by_branch_party
      def remove_index(options = {})
        @base.remove_index(@table_name, options)
      end

      # Removes the timestamp columns (+created_at+ and +updated_at+) from the table.
      # ===== Example
      #  t.remove_timestamps
      def remove_timestamps
        @base.remove_timestamps(@table_name)
      end

      # Renames a column.
      # ===== Example
      #  t.rename(:description, :name)
      def rename(column_name, new_column_name)
        @base.rename_column(@table_name, column_name, new_column_name)
      end

      # Adds a reference. Optionally adds a +type+ column, if <tt>:polymorphic</tt> option is provided.
      # <tt>references</tt> and <tt>belongs_to</tt> are acceptable.
      # ===== Examples
      #  t.references(:goat)
      #  t.references(:goat, :polymorphic => true)
      #  t.belongs_to(:goat)
      def references(*args)
        options = args.extract_options!
        polymorphic = options.delete(:polymorphic)
        args.each do |col|
          @base.add_column(@table_name, "#{col}_id", :integer, options)
          @base.add_column(@table_name, "#{col}_type", :string, polymorphic.is_a?(Hash) ? polymorphic : options) unless polymorphic.nil?
        end
      end
      alias :belongs_to :references

      # Removes a reference. Optionally removes a +type+ column.
      # <tt>remove_references</tt> and <tt>remove_belongs_to</tt> are acceptable.
      # ===== Examples
      #  t.remove_references(:goat)
      #  t.remove_references(:goat, :polymorphic => true)
      #  t.remove_belongs_to(:goat)
      def remove_references(*args)
        options = args.extract_options!
        polymorphic = options.delete(:polymorphic)
        args.each do |col|
          @base.remove_column(@table_name, "#{col}_id")
          @base.remove_column(@table_name, "#{col}_type") unless polymorphic.nil?
        end
      end
      alias :remove_belongs_to  :remove_references

      # Adds a column or columns of a specified type
      # ===== Examples
      #  t.string(:goat)
      #  t.string(:goat, :sheep)
      %w( string text integer float decimal datetime timestamp time date binary boolean ).each do |column_type|
        class_eval <<-EOV, __FILE__, __LINE__ + 1
          def #{column_type}(*args)                                          # def string(*args)
            options = args.extract_options!                                  #   options = args.extract_options!
            column_names = args                                              #   column_names = args
            type = :'#{column_type}'                                         #   type = :string
            column_names.each do |name|                                      #   column_names.each do |name|
              column = ColumnDefinition.new(@base, name.to_s, type)          #     column = ColumnDefinition.new(@base, name, type)
              if options[:limit]                                             #     if options[:limit]
                column.limit = options[:limit]                               #       column.limit = options[:limit]
              elsif native[type].is_a?(Hash)                                 #     elsif native[type].is_a?(Hash)
                column.limit = native[type][:limit]                          #       column.limit = native[type][:limit]
              end                                                            #     end
              column.precision = options[:precision]                         #     column.precision = options[:precision]
              column.scale = options[:scale]                                 #     column.scale = options[:scale]
              column.default = options[:default]                             #     column.default = options[:default]
              column.null = options[:null]                                   #     column.null = options[:null]
              @base.add_column(@table_name, name, column.sql_type, options)  #     @base.add_column(@table_name, name, column.sql_type, options)
            end                                                              #   end
          end                                                                # end
        EOV
      end

      private
        def native
          @base.native_database_types
        end
    end

  end
end
require 'active_support/core_ext/array/wrap'
require 'active_support/deprecation/reporting'

module ActiveRecord
  module ConnectionAdapters # :nodoc:
    module SchemaStatements
      # Returns a Hash of mappings from the abstract data types to the native
      # database types. See TableDefinition#column for details on the recognized
      # abstract data types.
      def native_database_types
        {}
      end

      # Truncates a table alias according to the limits of the current adapter.
      def table_alias_for(table_name)
        table_name[0...table_alias_length].gsub(/\./, '_')
      end

      # Checks to see if the table +table_name+ exists on the database.
      #
      # === Example
      #   table_exists?(:developers)
      def table_exists?(table_name)
        tables.include?(table_name.to_s)
      end

      # Returns an array of indexes for the given table.
      # def indexes(table_name, name = nil) end

      # Checks to see if an index exists on a table for a given index definition.
      #
      # === Examples
      #  # Check an index exists
      #  index_exists?(:suppliers, :company_id)
      #
      #  # Check an index on multiple columns exists
      #  index_exists?(:suppliers, [:company_id, :company_type])
      #
      #  # Check a unique index exists
      #  index_exists?(:suppliers, :company_id, :unique => true)
      #
      #  # Check an index with a custom name exists
      #  index_exists?(:suppliers, :company_id, :name => "idx_company_id"
      def index_exists?(table_name, column_name, options = {})
        column_names = Array.wrap(column_name)
        index_name = options.key?(:name) ? options[:name].to_s : index_name(table_name, :column => column_names)
        if options[:unique]
          indexes(table_name).any?{ |i| i.unique && i.name == index_name }
        else
          indexes(table_name).any?{ |i| i.name == index_name }
        end
      end

      # Returns an array of Column objects for the table specified by +table_name+.
      # See the concrete implementation for details on the expected parameter values.
      def columns(table_name, name = nil) end

      # Checks to see if a column exists in a given table.
      #
      # === Examples
      #  # Check a column exists
      #  column_exists?(:suppliers, :name)
      #
      #  # Check a column exists of a particular type
      #  column_exists?(:suppliers, :name, :string)
      #
      #  # Check a column exists with a specific definition
      #  column_exists?(:suppliers, :name, :string, :limit => 100)
      def column_exists?(table_name, column_name, type = nil, options = {})
        columns(table_name).any?{ |c| c.name == column_name.to_s &&
                                      (!type                 || c.type == type) &&
                                      (!options[:limit]      || c.limit == options[:limit]) &&
                                      (!options[:precision]  || c.precision == options[:precision]) &&
                                      (!options[:scale]      || c.scale == options[:scale]) }
      end

      # Creates a new table with the name +table_name+. +table_name+ may either
      # be a String or a Symbol.
      #
      # There are two ways to work with +create_table+. You can use the block
      # form or the regular form, like this:
      #
      # === Block form
      #  # create_table() passes a TableDefinition object to the block.
      #  # This form will not only create the table, but also columns for the
      #  # table.
      #
      #  create_table(:suppliers) do |t|
      #    t.column :name, :string, :limit => 60
      #    # Other fields here
      #  end
      #
      # === Block form, with shorthand
      #  # You can also use the column types as method calls, rather than calling the column method.
      #  create_table(:suppliers) do |t|
      #    t.string :name, :limit => 60
      #    # Other fields here
      #  end
      #
      # === Regular form
      #  # Creates a table called 'suppliers' with no columns.
      #  create_table(:suppliers)
      #  # Add a column to 'suppliers'.
      #  add_column(:suppliers, :name, :string, {:limit => 60})
      #
      # The +options+ hash can include the following keys:
      # [<tt>:id</tt>]
      #   Whether to automatically add a primary key column. Defaults to true.
      #   Join tables for +has_and_belongs_to_many+ should set it to false.
      # [<tt>:primary_key</tt>]
      #   The name of the primary key, if one is to be added automatically.
      #   Defaults to +id+. If <tt>:id</tt> is false this option is ignored.
      #
      #   Also note that this just sets the primary key in the table. You additionally
      #   need to configure the primary key in the model via +self.primary_key=+.
      #   Models do NOT auto-detect the primary key from their table definition.
      #
      # [<tt>:options</tt>]
      #   Any extra options you want appended to the table definition.
      # [<tt>:temporary</tt>]
      #   Make a temporary table.
      # [<tt>:force</tt>]
      #   Set to true to drop the table before creating it.
      #   Defaults to false.
      #
      # ===== Examples
      # ====== Add a backend specific option to the generated SQL (MySQL)
      #  create_table(:suppliers, :options => 'ENGINE=InnoDB DEFAULT CHARSET=utf8')
      # generates:
      #  CREATE TABLE suppliers (
      #    id int(11) DEFAULT NULL auto_increment PRIMARY KEY
      #  ) ENGINE=InnoDB DEFAULT CHARSET=utf8
      #
      # ====== Rename the primary key column
      #  create_table(:objects, :primary_key => 'guid') do |t|
      #    t.column :name, :string, :limit => 80
      #  end
      # generates:
      #  CREATE TABLE objects (
      #    guid int(11) DEFAULT NULL auto_increment PRIMARY KEY,
      #    name varchar(80)
      #  )
      #
      # ====== Do not add a primary key column
      #  create_table(:categories_suppliers, :id => false) do |t|
      #    t.column :category_id, :integer
      #    t.column :supplier_id, :integer
      #  end
      # generates:
      #  CREATE TABLE categories_suppliers (
      #    category_id int,
      #    supplier_id int
      #  )
      #
      # See also TableDefinition#column for details on how to create columns.
      def create_table(table_name, options = {})
        td = table_definition
        td.primary_key(options[:primary_key] || Base.get_primary_key(table_name.to_s.singularize)) unless options[:id] == false

        yield td if block_given?

        if options[:force] && table_exists?(table_name)
          drop_table(table_name, options)
        end

        create_sql = "CREATE#{' TEMPORARY' if options[:temporary]} TABLE "
        create_sql << "#{quote_table_name(table_name)} ("
        create_sql << td.to_sql
        create_sql << ") #{options[:options]}"
        execute create_sql
      end

      # A block for changing columns in +table+.
      #
      # === Example
      #  # change_table() yields a Table instance
      #  change_table(:suppliers) do |t|
      #    t.column :name, :string, :limit => 60
      #    # Other column alterations here
      #  end
      #
      # The +options+ hash can include the following keys:
      # [<tt>:bulk</tt>]
      #   Set this to true to make this a bulk alter query, such as
      #   ALTER TABLE `users` ADD COLUMN age INT(11), ADD COLUMN birthdate DATETIME ...
      #
      #   Defaults to false.
      #
      # ===== Examples
      # ====== Add a column
      #  change_table(:suppliers) do |t|
      #    t.column :name, :string, :limit => 60
      #  end
      #
      # ====== Add 2 integer columns
      #  change_table(:suppliers) do |t|
      #    t.integer :width, :height, :null => false, :default => 0
      #  end
      #
      # ====== Add created_at/updated_at columns
      #  change_table(:suppliers) do |t|
      #    t.timestamps
      #  end
      #
      # ====== Add a foreign key column
      #  change_table(:suppliers) do |t|
      #    t.references :company
      #  end
      #
      # Creates a <tt>company_id(integer)</tt> column
      #
      # ====== Add a polymorphic foreign key column
      #  change_table(:suppliers) do |t|
      #    t.belongs_to :company, :polymorphic => true
      #  end
      #
      # Creates <tt>company_type(varchar)</tt> and <tt>company_id(integer)</tt> columns
      #
      # ====== Remove a column
      #  change_table(:suppliers) do |t|
      #    t.remove :company
      #  end
      #
      # ====== Remove several columns
      #  change_table(:suppliers) do |t|
      #    t.remove :company_id
      #    t.remove :width, :height
      #  end
      #
      # ====== Remove an index
      #  change_table(:suppliers) do |t|
      #    t.remove_index :company_id
      #  end
      #
      # See also Table for details on
      # all of the various column transformation
      def change_table(table_name, options = {})
        if supports_bulk_alter? && options[:bulk]
          recorder = ActiveRecord::Migration::CommandRecorder.new(self)
          yield Table.new(table_name, recorder)
          bulk_change_table(table_name, recorder.commands)
        else
          yield Table.new(table_name, self)
        end
      end

      # Renames a table.
      # ===== Example
      #  rename_table('octopuses', 'octopi')
      def rename_table(table_name, new_name)
        raise NotImplementedError, "rename_table is not implemented"
      end

      # Drops a table from the database.
      def drop_table(table_name, options = {})
        execute "DROP TABLE #{quote_table_name(table_name)}"
      end

      # Adds a new column to the named table.
      # See TableDefinition#column for details of the options you can use.
      def add_column(table_name, column_name, type, options = {})
        add_column_sql = "ALTER TABLE #{quote_table_name(table_name)} ADD #{quote_column_name(column_name)} #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"
        add_column_options!(add_column_sql, options)
        execute(add_column_sql)
      end

      # Removes the column(s) from the table definition.
      # ===== Examples
      #  remove_column(:suppliers, :qualification)
      #  remove_columns(:suppliers, :qualification, :experience)
      def remove_column(table_name, *column_names)
        if column_names.flatten!
          message = 'Passing array to remove_columns is deprecated, please use ' +
                    'multiple arguments, like: `remove_columns(:posts, :foo, :bar)`'
          ActiveSupport::Deprecation.warn message, caller
        end

        columns_for_remove(table_name, *column_names).each do |column_name|
          execute "ALTER TABLE #{quote_table_name(table_name)} DROP #{column_name}"
        end
      end
      alias :remove_columns :remove_column

      # Changes the column's definition according to the new options.
      # See TableDefinition#column for details of the options you can use.
      # ===== Examples
      #  change_column(:suppliers, :name, :string, :limit => 80)
      #  change_column(:accounts, :description, :text)
      def change_column(table_name, column_name, type, options = {})
        raise NotImplementedError, "change_column is not implemented"
      end

      # Sets a new default value for a column.
      # ===== Examples
      #  change_column_default(:suppliers, :qualification, 'new')
      #  change_column_default(:accounts, :authorized, 1)
      #  change_column_default(:users, :email, nil)
      def change_column_default(table_name, column_name, default)
        raise NotImplementedError, "change_column_default is not implemented"
      end

      # Renames a column.
      # ===== Example
      #  rename_column(:suppliers, :description, :name)
      def rename_column(table_name, column_name, new_column_name)
        raise NotImplementedError, "rename_column is not implemented"
      end

      # Adds a new index to the table. +column_name+ can be a single Symbol, or
      # an Array of Symbols.
      #
      # The index will be named after the table and the column name(s), unless
      # you pass <tt>:name</tt> as an option.
      #
      # ===== Examples
      #
      # ====== Creating a simple index
      #  add_index(:suppliers, :name)
      # generates
      #  CREATE INDEX suppliers_name_index ON suppliers(name)
      #
      # ====== Creating a unique index
      #  add_index(:accounts, [:branch_id, :party_id], :unique => true)
      # generates
      #  CREATE UNIQUE INDEX accounts_branch_id_party_id_index ON accounts(branch_id, party_id)
      #
      # ====== Creating a named index
      #  add_index(:accounts, [:branch_id, :party_id], :unique => true, :name => 'by_branch_party')
      # generates
      #  CREATE UNIQUE INDEX by_branch_party ON accounts(branch_id, party_id)
      #
      # ====== Creating an index with specific key length
      #  add_index(:accounts, :name, :name => 'by_name', :length => 10)
      # generates
      #  CREATE INDEX by_name ON accounts(name(10))
      #
      #  add_index(:accounts, [:name, :surname], :name => 'by_name_surname', :length => {:name => 10, :surname => 15})
      # generates
      #  CREATE INDEX by_name_surname ON accounts(name(10), surname(15))
      #
      # Note: SQLite doesn't support index length
      #
      # ====== Creating an index with a sort order (desc or asc, asc is the default)
      #  add_index(:accounts, [:branch_id, :party_id, :surname], :order => {:branch_id => :desc, :part_id => :asc})
      # generates
      #  CREATE INDEX by_branch_desc_party ON accounts(branch_id DESC, party_id ASC, surname)
      #
      # Note: mysql doesn't yet support index order (it accepts the syntax but ignores it)
      #
      def add_index(table_name, column_name, options = {})
        index_name, index_type, index_columns = add_index_options(table_name, column_name, options)
        execute "CREATE #{index_type} INDEX #{quote_column_name(index_name)} ON #{quote_table_name(table_name)} (#{index_columns})"
      end

      # Remove the given index from the table.
      #
      # Remove the index_accounts_on_column in the accounts table.
      #   remove_index :accounts, :column
      # Remove the index named index_accounts_on_branch_id in the accounts table.
      #   remove_index :accounts, :column => :branch_id
      # Remove the index named index_accounts_on_branch_id_and_party_id in the accounts table.
      #   remove_index :accounts, :column => [:branch_id, :party_id]
      # Remove the index named by_branch_party in the accounts table.
      #   remove_index :accounts, :name => :by_branch_party
      def remove_index(table_name, options = {})
        remove_index!(table_name, index_name_for_remove(table_name, options))
      end

      def remove_index!(table_name, index_name) #:nodoc:
        execute "DROP INDEX #{quote_column_name(index_name)} ON #{quote_table_name(table_name)}"
      end

      # Rename an index.
      #
      # Rename the index_people_on_last_name index to index_users_on_last_name
      #   rename_index :people, 'index_people_on_last_name', 'index_users_on_last_name'
      def rename_index(table_name, old_name, new_name)
        # this is a naive implementation; some DBs may support this more efficiently (Postgres, for instance)
        old_index_def = indexes(table_name).detect { |i| i.name == old_name }
        return unless old_index_def
        remove_index(table_name, :name => old_name)
        add_index(table_name, old_index_def.columns, :name => new_name, :unique => old_index_def.unique)
      end

      def index_name(table_name, options) #:nodoc:
        if Hash === options # legacy support
          if options[:column]
            "index_#{table_name}_on_#{Array.wrap(options[:column]) * '_and_'}"
          elsif options[:name]
            options[:name]
          else
            raise ArgumentError, "You must specify the index name"
          end
        else
          index_name(table_name, :column => options)
        end
      end

      # Verify the existence of an index with a given name.
      #
      # The default argument is returned if the underlying implementation does not define the indexes method,
      # as there's no way to determine the correct answer in that case.
      def index_name_exists?(table_name, index_name, default)
        return default unless respond_to?(:indexes)
        index_name = index_name.to_s
        indexes(table_name).detect { |i| i.name == index_name }
      end

      # Returns a string of <tt>CREATE TABLE</tt> SQL statement(s) for recreating the
      # entire structure of the database.
      def structure_dump
      end

      def dump_schema_information #:nodoc:
        sm_table = ActiveRecord::Migrator.schema_migrations_table_name
        migrated = select_values("SELECT version FROM #{sm_table} ORDER BY version")
        migrated.map { |v| "INSERT INTO #{sm_table} (version) VALUES ('#{v}');" }.join("\n\n")
      end

      # Should not be called normally, but this operation is non-destructive.
      # The migrations module handles this automatically.
      def initialize_schema_migrations_table
        sm_table = ActiveRecord::Migrator.schema_migrations_table_name

        unless table_exists?(sm_table)
          create_table(sm_table, :id => false) do |schema_migrations_table|
            schema_migrations_table.column :version, :string, :null => false
          end
          add_index sm_table, :version, :unique => true,
            :name => "#{Base.table_name_prefix}unique_schema_migrations#{Base.table_name_suffix}"

          # Backwards-compatibility: if we find schema_info, assume we've
          # migrated up to that point:
          si_table = Base.table_name_prefix + 'schema_info' + Base.table_name_suffix

          if table_exists?(si_table)
            ActiveSupport::Deprecation.warn "Usage of the schema table `#{si_table}` is deprecated. Please switch to using `schema_migrations` table"

            old_version = select_value("SELECT version FROM #{quote_table_name(si_table)}").to_i
            assume_migrated_upto_version(old_version)
            drop_table(si_table)
          end
        end
      end

      def assume_migrated_upto_version(version, migrations_paths = ActiveRecord::Migrator.migrations_paths)
        migrations_paths = Array.wrap(migrations_paths)
        version = version.to_i
        sm_table = quote_table_name(ActiveRecord::Migrator.schema_migrations_table_name)

        migrated = select_values("SELECT version FROM #{sm_table}").map { |v| v.to_i }
        paths = migrations_paths.map {|p| "#{p}/[0-9]*_*.rb" }
        versions = Dir[*paths].map do |filename|
          filename.split('/').last.split('_').first.to_i
        end

        unless migrated.include?(version)
          execute "INSERT INTO #{sm_table} (version) VALUES ('#{version}')"
        end

        inserted = Set.new
        (versions - migrated).each do |v|
          if inserted.include?(v)
            raise "Duplicate migration #{v}. Please renumber your migrations to resolve the conflict."
          elsif v < version
            execute "INSERT INTO #{sm_table} (version) VALUES ('#{v}')"
            inserted << v
          end
        end
      end

      def type_to_sql(type, limit = nil, precision = nil, scale = nil) #:nodoc:
        if native = native_database_types[type.to_sym]
          column_type_sql = (native.is_a?(Hash) ? native[:name] : native).dup

          if type == :decimal # ignore limit, use precision and scale
            scale ||= native[:scale]

            if precision ||= native[:precision]
              if scale
                column_type_sql << "(#{precision},#{scale})"
              else
                column_type_sql << "(#{precision})"
              end
            elsif scale
              raise ArgumentError, "Error adding decimal column: precision cannot be empty if scale if specified"
            end

          elsif (type != :primary_key) && (limit ||= native.is_a?(Hash) && native[:limit])
            column_type_sql << "(#{limit})"
          end

          column_type_sql
        else
          type
        end
      end

      def add_column_options!(sql, options) #:nodoc:
        sql << " DEFAULT #{quote(options[:default], options[:column])}" if options_include_default?(options)
        # must explicitly check for :null to allow change_column to work on migrations
        if options[:null] == false
          sql << " NOT NULL"
        end
      end

      # SELECT DISTINCT clause for a given set of columns and a given ORDER BY clause.
      # Both PostgreSQL and Oracle overrides this for custom DISTINCT syntax.
      #
      #   distinct("posts.id", "posts.created_at desc")
      def distinct(columns, order_by)
        "DISTINCT #{columns}"
      end

      # Adds timestamps (created_at and updated_at) columns to the named table.
      # ===== Examples
      #  add_timestamps(:suppliers)
      def add_timestamps(table_name)
        add_column table_name, :created_at, :datetime
        add_column table_name, :updated_at, :datetime
      end

      # Removes the timestamp columns (created_at and updated_at) from the table definition.
      # ===== Examples
      #  remove_timestamps(:suppliers)
      def remove_timestamps(table_name)
        remove_column table_name, :updated_at
        remove_column table_name, :created_at
      end

      protected
        def add_index_sort_order(option_strings, column_names, options = {})
          if options.is_a?(Hash) && order = options[:order]
            case order
            when Hash
              column_names.each {|name| option_strings[name] += " #{order[name].to_s.upcase}" if order.has_key?(name)}
            when String
              column_names.each {|name| option_strings[name] += " #{order.upcase}"}
            end
          end

          return option_strings
        end

        # Overridden by the mysql adapter for supporting index lengths
        def quoted_columns_for_index(column_names, options = {})
          option_strings = Hash[column_names.map {|name| [name, '']}]

          # add index sort order if supported
          if supports_index_sort_order?
            option_strings = add_index_sort_order(option_strings, column_names, options)
          end

          column_names.map {|name| quote_column_name(name) + option_strings[name]}
        end

        def options_include_default?(options)
          options.include?(:default) && !(options[:null] == false && options[:default].nil?)
        end

        def add_index_options(table_name, column_name, options = {})
          column_names = Array.wrap(column_name)
          index_name   = index_name(table_name, :column => column_names)

          if Hash === options # legacy support, since this param was a string
            index_type = options[:unique] ? "UNIQUE" : ""
            index_name = options[:name].to_s if options.key?(:name)
          else
            index_type = options
          end

          if index_name.length > index_name_length
            raise ArgumentError, "Index name '#{index_name}' on table '#{table_name}' is too long; the limit is #{index_name_length} characters"
          end
          if index_name_exists?(table_name, index_name, false)
            raise ArgumentError, "Index name '#{index_name}' on table '#{table_name}' already exists"
          end
          index_columns = quoted_columns_for_index(column_names, options).join(", ")

          [index_name, index_type, index_columns]
        end

        def index_name_for_remove(table_name, options = {})
          index_name = index_name(table_name, options)

          unless index_name_exists?(table_name, index_name, true)
            raise ArgumentError, "Index name '#{index_name}' on table '#{table_name}' does not exist"
          end

          index_name
        end

        def columns_for_remove(table_name, *column_names)
          column_names = column_names.flatten

          raise ArgumentError.new("You must specify at least one column name. Example: remove_column(:people, :first_name)") if column_names.blank?
          column_names.map {|column_name| quote_column_name(column_name) }
        end

      private
      def table_definition
        TableDefinition.new(self)
      end
    end
  end
end
require 'date'
require 'bigdecimal'
require 'bigdecimal/util'
require 'active_support/core_ext/benchmark'
require 'active_support/deprecation'
require 'active_record/connection_adapters/schema_cache'
require 'monitor'

module ActiveRecord
  module ConnectionAdapters # :nodoc:
    extend ActiveSupport::Autoload

    autoload :Column

    autoload_under 'abstract' do
      autoload :IndexDefinition,  'active_record/connection_adapters/abstract/schema_definitions'
      autoload :ColumnDefinition, 'active_record/connection_adapters/abstract/schema_definitions'
      autoload :TableDefinition,  'active_record/connection_adapters/abstract/schema_definitions'
      autoload :Table,            'active_record/connection_adapters/abstract/schema_definitions'

      autoload :SchemaStatements
      autoload :DatabaseStatements
      autoload :DatabaseLimits
      autoload :Quoting

      autoload :ConnectionPool
      autoload :ConnectionHandler,       'active_record/connection_adapters/abstract/connection_pool'
      autoload :ConnectionManagement,    'active_record/connection_adapters/abstract/connection_pool'
      autoload :ConnectionSpecification

      autoload :QueryCache
    end

    # Active Record supports multiple database systems. AbstractAdapter and
    # related classes form the abstraction layer which makes this possible.
    # An AbstractAdapter represents a connection to a database, and provides an
    # abstract interface for database-specific functionality such as establishing
    # a connection, escaping values, building the right SQL fragments for ':offset'
    # and ':limit' options, etc.
    #
    # All the concrete database adapters follow the interface laid down in this class.
    # ActiveRecord::Base.connection returns an AbstractAdapter object, which
    # you can use.
    #
    # Most of the methods in the adapter are useful during migrations. Most
    # notably, the instance methods provided by SchemaStatement are very useful.
    class AbstractAdapter
      include Quoting, DatabaseStatements, SchemaStatements
      include DatabaseLimits
      include QueryCache
      include ActiveSupport::Callbacks
      include MonitorMixin

      define_callbacks :checkout, :checkin

      attr_accessor :visitor, :pool
      attr_reader :schema_cache, :last_use, :in_use, :logger
      alias :in_use? :in_use

      def initialize(connection, logger = nil, pool = nil) #:nodoc:
        super()

        @active              = nil
        @connection          = connection
        @in_use              = false
        @instrumenter        = ActiveSupport::Notifications.instrumenter
        @last_use            = false
        @logger              = logger
        @open_transactions   = 0
        @pool                = pool
        @query_cache         = Hash.new { |h,sql| h[sql] = {} }
        @query_cache_enabled = false
        @schema_cache        = SchemaCache.new self
        @visitor             = nil
      end

      def lease
        synchronize do
          unless in_use
            @in_use   = true
            @last_use = Time.now
          end
        end
      end

      def expire
        @in_use = false
      end

      # Returns the human-readable name of the adapter. Use mixed case - one
      # can always use downcase if needed.
      def adapter_name
        'Abstract'
      end

      # Does this adapter support migrations? Backend specific, as the
      # abstract adapter always returns +false+.
      def supports_migrations?
        false
      end

      # Can this adapter determine the primary key for tables not attached
      # to an Active Record class, such as join tables? Backend specific, as
      # the abstract adapter always returns +false+.
      def supports_primary_key?
        false
      end

      # Does this adapter support using DISTINCT within COUNT? This is +true+
      # for all adapters except sqlite.
      def supports_count_distinct?
        true
      end

      # Does this adapter support DDL rollbacks in transactions? That is, would
      # CREATE TABLE or ALTER TABLE get rolled back by a transaction? PostgreSQL,
      # SQL Server, and others support this. MySQL and others do not.
      def supports_ddl_transactions?
        false
      end

      def supports_bulk_alter?
        false
      end

      # Does this adapter support savepoints? PostgreSQL and MySQL do,
      # SQLite < 3.6.8 does not.
      def supports_savepoints?
        false
      end

      # Should primary key values be selected from their corresponding
      # sequence before the insert statement? If true, next_sequence_value
      # is called before each insert to set the record's primary key.
      # This is false for all adapters but Firebird.
      def prefetch_primary_key?(table_name = nil)
        false
      end

      # Does this adapter support index sort order?
      def supports_index_sort_order?
        false
      end

      # Does this adapter support explain? As of this writing sqlite3,
      # mysql2, and postgresql are the only ones that do.
      def supports_explain?
        false
      end

      # QUOTING ==================================================

      # Override to return the quoted table name. Defaults to column quoting.
      def quote_table_name(name)
        quote_column_name(name)
      end

      # Returns a bind substitution value given a +column+ and list of current
      # +binds+
      def substitute_at(column, index)
        Arel::Nodes::BindParam.new '?'
      end

      # REFERENTIAL INTEGRITY ====================================

      # Override to turn off referential integrity while executing <tt>&block</tt>.
      def disable_referential_integrity
        yield
      end

      # CONNECTION MANAGEMENT ====================================

      # Checks whether the connection to the database is still active. This includes
      # checking whether the database is actually capable of responding, i.e. whether
      # the connection isn't stale.
      def active?
        @active != false
      end

      # Disconnects from the database if already connected, and establishes a
      # new connection with the database.
      def reconnect!
        @active = true
      end

      # Disconnects from the database if already connected. Otherwise, this
      # method does nothing.
      def disconnect!
        @active = false
      end

      # Reset the state of this connection, directing the DBMS to clear
      # transactions and other connection-related server-side state. Usually a
      # database-dependent operation.
      #
      # The default implementation does nothing; the implementation should be
      # overridden by concrete adapters.
      def reset!
        # this should be overridden by concrete adapters
      end

      ###
      # Clear any caching the database adapter may be doing, for example
      # clearing the prepared statement cache. This is database specific.
      def clear_cache!
        # this should be overridden by concrete adapters
      end

      # Returns true if its required to reload the connection between requests for development mode.
      # This is not the case for Ruby/MySQL and it's not necessary for any adapters except SQLite.
      def requires_reloading?
        false
      end

      # Checks whether the connection to the database is still active (i.e. not stale).
      # This is done under the hood by calling <tt>active?</tt>. If the connection
      # is no longer active, then this method will reconnect to the database.
      def verify!(*ignored)
        reconnect! unless active?
      end

      # Provides access to the underlying database driver for this adapter. For
      # example, this method returns a Mysql object in case of MysqlAdapter,
      # and a PGconn object in case of PostgreSQLAdapter.
      #
      # This is useful for when you need to call a proprietary method such as
      # PostgreSQL's lo_* methods.
      def raw_connection
        @connection
      end

      attr_reader :open_transactions

      def increment_open_transactions
        @open_transactions += 1
      end

      def decrement_open_transactions
        @open_transactions -= 1
      end

      def transaction_joinable=(joinable)
        @transaction_joinable = joinable
      end

      def create_savepoint
      end

      def rollback_to_savepoint
      end

      def release_savepoint
      end

      def case_sensitive_modifier(node)
        node
      end

      def case_insensitive_comparison(table, attribute, column, value)
        table[attribute].lower.eq(table.lower(value))
      end

      def current_savepoint_name
        "active_record_#{open_transactions}"
      end

      # Check the connection back in to the connection pool
      def close
        pool.checkin self
      end

      protected

        def log(sql, name = "SQL", binds = [])
          @instrumenter.instrument(
            "sql.active_record",
            :sql           => sql,
            :name          => name,
            :connection_id => object_id,
            :binds         => binds) { yield }
        rescue Exception => e
          message = "#{e.class.name}: #{e.message}: #{sql}"
          @logger.debug message if @logger
          exception = translate_exception(e, message)
          exception.set_backtrace e.backtrace
          raise exception
        end

        def translate_exception(e, message)
          # override in derived class
          ActiveRecord::StatementInvalid.new(message)
        end

    end
  end
end
require 'active_support/core_ext/object/blank'
require 'arel/visitors/bind_visitor'

module ActiveRecord
  module ConnectionAdapters
    class AbstractMysqlAdapter < AbstractAdapter
      class Column < ConnectionAdapters::Column # :nodoc:
        attr_reader :collation

        def initialize(name, default, sql_type = nil, null = true, collation = nil)
          super(name, default, sql_type, null)
          @collation = collation
        end

        def extract_default(default)
          if sql_type =~ /blob/i || type == :text
            if default.blank?
              return null ? nil : ''
            else
              raise ArgumentError, "#{type} columns cannot have a default value: #{default.inspect}"
            end
          elsif missing_default_forged_as_empty_string?(default)
            nil
          else
            super
          end
        end

        def has_default?
          return false if sql_type =~ /blob/i || type == :text #mysql forbids defaults on blob and text columns
          super
        end

        # Must return the relevant concrete adapter
        def adapter
          raise NotImplementedError
        end

        def case_sensitive?
          collation && !collation.match(/_ci$/)
        end

        private

        def simplified_type(field_type)
          return :boolean if adapter.emulate_booleans && field_type.downcase.index("tinyint(1)")

          case field_type
          when /enum/i, /set/i then :string
          when /year/i         then :integer
          when /bit/i          then :binary
          else
            super
          end
        end

        def extract_limit(sql_type)
          case sql_type
          when /blob|text/i
            case sql_type
            when /tiny/i
              255
            when /medium/i
              16777215
            when /long/i
              2147483647 # mysql only allows 2^31-1, not 2^32-1, somewhat inconsistently with the tiny/medium/normal cases
            else
              super # we could return 65535 here, but we leave it undecorated by default
            end
          when /^bigint/i;    8
          when /^int/i;       4
          when /^mediumint/i; 3
          when /^smallint/i;  2
          when /^tinyint/i;   1
          when /^enum\((.+)\)/i
            $1.split(',').map{|enum| enum.strip.length - 2}.max
          else
            super
          end
        end

        # MySQL misreports NOT NULL column default when none is given.
        # We can't detect this for columns which may have a legitimate ''
        # default (string) but we can for others (integer, datetime, boolean,
        # and the rest).
        #
        # Test whether the column has default '', is not null, and is not
        # a type allowing default ''.
        def missing_default_forged_as_empty_string?(default)
          type != :string && !null && default == ''
        end
      end

      ##
      # :singleton-method:
      # By default, the MysqlAdapter will consider all columns of type <tt>tinyint(1)</tt>
      # as boolean. If you wish to disable this emulation (which was the default
      # behavior in versions 0.13.1 and earlier) you can add the following line
      # to your application.rb file:
      #
      #   ActiveRecord::ConnectionAdapters::Mysql[2]Adapter.emulate_booleans = false
      class_attribute :emulate_booleans
      self.emulate_booleans = true

      LOST_CONNECTION_ERROR_MESSAGES = [
        "Server shutdown in progress",
        "Broken pipe",
        "Lost connection to MySQL server during query",
        "MySQL server has gone away" ]

      QUOTED_TRUE, QUOTED_FALSE = '1', '0'

      NATIVE_DATABASE_TYPES = {
        :primary_key => "int(11) DEFAULT NULL auto_increment PRIMARY KEY",
        :string      => { :name => "varchar", :limit => 255 },
        :text        => { :name => "text" },
        :integer     => { :name => "int", :limit => 4 },
        :float       => { :name => "float" },
        :decimal     => { :name => "decimal" },
        :datetime    => { :name => "datetime" },
        :timestamp   => { :name => "datetime" },
        :time        => { :name => "time" },
        :date        => { :name => "date" },
        :binary      => { :name => "blob" },
        :boolean     => { :name => "tinyint", :limit => 1 }
      }

      class BindSubstitution < Arel::Visitors::MySQL # :nodoc:
        include Arel::Visitors::BindVisitor
      end

      # FIXME: Make the first parameter more similar for the two adapters
      def initialize(connection, logger, connection_options, config)
        super(connection, logger)
        @connection_options, @config = connection_options, config
        @quoted_column_names, @quoted_table_names = {}, {}

        if config.fetch(:prepared_statements) { true }
          @visitor = Arel::Visitors::MySQL.new self
        else
          @visitor = BindSubstitution.new self
        end
      end

      def adapter_name #:nodoc:
        self.class::ADAPTER_NAME
      end

      # Returns true, since this connection adapter supports migrations.
      def supports_migrations?
        true
      end

      def supports_primary_key?
        true
      end

      # Returns true, since this connection adapter supports savepoints.
      def supports_savepoints?
        true
      end

      def supports_bulk_alter? #:nodoc:
        true
      end

      # Technically MySQL allows to create indexes with the sort order syntax
      # but at the moment (5.5) it doesn't yet implement them
      def supports_index_sort_order?
        true
      end

      def native_database_types
        NATIVE_DATABASE_TYPES
      end

      # HELPER METHODS ===========================================

      # The two drivers have slightly different ways of yielding hashes of results, so
      # this method must be implemented to provide a uniform interface.
      def each_hash(result) # :nodoc:
        raise NotImplementedError
      end

      # Overridden by the adapters to instantiate their specific Column type.
      def new_column(field, default, type, null, collation) # :nodoc:
        Column.new(field, default, type, null, collation)
      end

      # Must return the Mysql error number from the exception, if the exception has an
      # error number.
      def error_number(exception) # :nodoc:
        raise NotImplementedError
      end

      # QUOTING ==================================================

      def quote(value, column = nil)
        if value.kind_of?(String) && column && column.type == :binary && column.class.respond_to?(:string_to_binary)
          s = column.class.string_to_binary(value).unpack("H*")[0]
          "x'#{s}'"
        else
          super
        end
      end

      def quote_column_name(name) #:nodoc:
        @quoted_column_names[name] ||= "`#{name.to_s.gsub('`', '``')}`"
      end

      def quote_table_name(name) #:nodoc:
        @quoted_table_names[name] ||= quote_column_name(name).gsub('.', '`.`')
      end

      def quoted_true
        QUOTED_TRUE
      end

      def quoted_false
        QUOTED_FALSE
      end

      # REFERENTIAL INTEGRITY ====================================

      def disable_referential_integrity(&block) #:nodoc:
        old = select_value("SELECT @@FOREIGN_KEY_CHECKS")

        begin
          update("SET FOREIGN_KEY_CHECKS = 0")
          yield
        ensure
          update("SET FOREIGN_KEY_CHECKS = #{old}")
        end
      end

      # DATABASE STATEMENTS ======================================

      # Executes the SQL statement in the context of this connection.
      def execute(sql, name = nil)
        if name == :skip_logging
          @connection.query(sql)
        else
          log(sql, name) { @connection.query(sql) }
        end
      rescue ActiveRecord::StatementInvalid => exception
        if exception.message.split(":").first =~ /Packets out of order/
          raise ActiveRecord::StatementInvalid, "'Packets out of order' error was received from the database. Please update your mysql bindings (gem install mysql) and read http://dev.mysql.com/doc/mysql/en/password-hashing.html for more information. If you're on Windows, use the Instant Rails installer to get the updated mysql bindings."
        else
          raise
        end
      end

      # MysqlAdapter has to free a result after using it, so we use this method to write
      # stuff in a abstract way without concerning ourselves about whether it needs to be
      # explicitly freed or not.
      def execute_and_free(sql, name = nil) #:nodoc:
        yield execute(sql, name)
      end

      def update_sql(sql, name = nil) #:nodoc:
        super
        @connection.affected_rows
      end

      def begin_db_transaction
        execute "BEGIN"
      rescue Exception
        # Transactions aren't supported
      end

      def commit_db_transaction #:nodoc:
        execute "COMMIT"
      rescue Exception
        # Transactions aren't supported
      end

      def rollback_db_transaction #:nodoc:
        execute "ROLLBACK"
      rescue Exception
        # Transactions aren't supported
      end

      def create_savepoint
        execute("SAVEPOINT #{current_savepoint_name}")
      end

      def rollback_to_savepoint
        execute("ROLLBACK TO SAVEPOINT #{current_savepoint_name}")
      end

      def release_savepoint
        execute("RELEASE SAVEPOINT #{current_savepoint_name}")
      end

      # In the simple case, MySQL allows us to place JOINs directly into the UPDATE
      # query. However, this does not allow for LIMIT, OFFSET and ORDER. To support
      # these, we must use a subquery. However, MySQL is too stupid to create a
      # temporary table for this automatically, so we have to give it some prompting
      # in the form of a subsubquery. Ugh!
      def join_to_update(update, select) #:nodoc:
        if select.limit || select.offset || select.orders.any?
          subsubselect = select.clone
          subsubselect.projections = [update.key]

          subselect = Arel::SelectManager.new(select.engine)
          subselect.project Arel.sql(update.key.name)
          subselect.from subsubselect.as('__active_record_temp')

          update.where update.key.in(subselect)
        else
          update.table select.source
          update.wheres = select.constraints
        end
      end

      # SCHEMA STATEMENTS ========================================

      def structure_dump #:nodoc:
        if supports_views?
          sql = "SHOW FULL TABLES WHERE Table_type = 'BASE TABLE'"
        else
          sql = "SHOW TABLES"
        end

        select_all(sql).map { |table|
          table.delete('Table_type')
          sql = "SHOW CREATE TABLE #{quote_table_name(table.to_a.first.last)}"
          exec_query(sql).first['Create Table'] + ";\n\n"
        }.join
      end

      # Drops the database specified on the +name+ attribute
      # and creates it again using the provided +options+.
      def recreate_database(name, options = {})
        drop_database(name)
        create_database(name, options)
      end

      # Create a new MySQL database with optional <tt>:charset</tt> and <tt>:collation</tt>.
      # Charset defaults to utf8.
      #
      # Example:
      #   create_database 'charset_test', :charset => 'latin1', :collation => 'latin1_bin'
      #   create_database 'matt_development'
      #   create_database 'matt_development', :charset => :big5
      def create_database(name, options = {})
        if options[:collation]
          execute "CREATE DATABASE `#{name}` DEFAULT CHARACTER SET `#{options[:charset] || 'utf8'}` COLLATE `#{options[:collation]}`"
        else
          execute "CREATE DATABASE `#{name}` DEFAULT CHARACTER SET `#{options[:charset] || 'utf8'}`"
        end
      end

      # Drops a MySQL database.
      #
      # Example:
      #   drop_database('sebastian_development')
      def drop_database(name) #:nodoc:
        execute "DROP DATABASE IF EXISTS `#{name}`"
      end

      def current_database
        select_value 'SELECT DATABASE() as db'
      end

      # Returns the database character set.
      def charset
        show_variable 'character_set_database'
      end

      # Returns the database collation strategy.
      def collation
        show_variable 'collation_database'
      end

      def tables(name = nil, database = nil, like = nil) #:nodoc:
        sql = "SHOW TABLES "
        sql << "IN #{quote_table_name(database)} " if database
        sql << "LIKE #{quote(like)}" if like

        execute_and_free(sql, 'SCHEMA') do |result|
          result.collect { |field| field.first }
        end
      end

      def table_exists?(name)
        return false unless name
        return true if tables(nil, nil, name).any?

        name          = name.to_s
        schema, table = name.split('.', 2)

        unless table # A table was provided without a schema
          table  = schema
          schema = nil
        end

        tables(nil, schema, table).any?
      end

      # Returns an array of indexes for the given table.
      def indexes(table_name, name = nil) #:nodoc:
        indexes = []
        current_index = nil
        execute_and_free("SHOW KEYS FROM #{quote_table_name(table_name)}", 'SCHEMA') do |result|
          each_hash(result) do |row|
            if current_index != row[:Key_name]
              next if row[:Key_name] == 'PRIMARY' # skip the primary key
              current_index = row[:Key_name]
              indexes << IndexDefinition.new(row[:Table], row[:Key_name], row[:Non_unique].to_i == 0, [], [])
            end

            indexes.last.columns << row[:Column_name]
            indexes.last.lengths << row[:Sub_part]
          end
        end

        indexes
      end

      # Returns an array of +Column+ objects for the table specified by +table_name+.
      def columns(table_name, name = nil)#:nodoc:
        sql = "SHOW FULL FIELDS FROM #{quote_table_name(table_name)}"
        execute_and_free(sql, 'SCHEMA') do |result|
          each_hash(result).map do |field|
            new_column(field[:Field], field[:Default], field[:Type], field[:Null] == "YES", field[:Collation])
          end
        end
      end

      def create_table(table_name, options = {}) #:nodoc:
        super(table_name, options.reverse_merge(:options => "ENGINE=InnoDB"))
      end

      def bulk_change_table(table_name, operations) #:nodoc:
        sqls = operations.map do |command, args|
          table, arguments = args.shift, args
          method = :"#{command}_sql"

          if respond_to?(method, true)
            send(method, table, *arguments)
          else
            raise "Unknown method called : #{method}(#{arguments.inspect})"
          end
        end.flatten.join(", ")

        execute("ALTER TABLE #{quote_table_name(table_name)} #{sqls}")
      end

      # Renames a table.
      #
      # Example:
      #   rename_table('octopuses', 'octopi')
      def rename_table(table_name, new_name)
        execute "RENAME TABLE #{quote_table_name(table_name)} TO #{quote_table_name(new_name)}"
      end

      def add_column(table_name, column_name, type, options = {})
        execute("ALTER TABLE #{quote_table_name(table_name)} #{add_column_sql(table_name, column_name, type, options)}")
      end

      def change_column_default(table_name, column_name, default)
        column = column_for(table_name, column_name)
        change_column table_name, column_name, column.sql_type, :default => default
      end

      def change_column_null(table_name, column_name, null, default = nil)
        column = column_for(table_name, column_name)

        unless null || default.nil?
          execute("UPDATE #{quote_table_name(table_name)} SET #{quote_column_name(column_name)}=#{quote(default)} WHERE #{quote_column_name(column_name)} IS NULL")
        end

        change_column table_name, column_name, column.sql_type, :null => null
      end

      def change_column(table_name, column_name, type, options = {}) #:nodoc:
        execute("ALTER TABLE #{quote_table_name(table_name)} #{change_column_sql(table_name, column_name, type, options)}")
      end

      def rename_column(table_name, column_name, new_column_name) #:nodoc:
        execute("ALTER TABLE #{quote_table_name(table_name)} #{rename_column_sql(table_name, column_name, new_column_name)}")
      end

      # Maps logical Rails types to MySQL-specific data types.
      def type_to_sql(type, limit = nil, precision = nil, scale = nil)
        case type.to_s
        when 'integer'
          case limit
          when 1; 'tinyint'
          when 2; 'smallint'
          when 3; 'mediumint'
          when nil, 4, 11; 'int(11)'  # compatibility with MySQL default
          when 5..8; 'bigint'
          else raise(ActiveRecordError, "No integer type has byte size #{limit}")
          end
        when 'text'
          case limit
          when 0..0xff;               'tinytext'
          when nil, 0x100..0xffff;    'text'
          when 0x10000..0xffffff;     'mediumtext'
          when 0x1000000..0xffffffff; 'longtext'
          else raise(ActiveRecordError, "No text type has character length #{limit}")
          end
        else
          super
        end
      end

      def add_column_position!(sql, options)
        if options[:first]
          sql << " FIRST"
        elsif options[:after]
          sql << " AFTER #{quote_column_name(options[:after])}"
        end
      end

      # SHOW VARIABLES LIKE 'name'
      def show_variable(name)
        variables = select_all("SHOW VARIABLES LIKE '#{name}'")
        variables.first['Value'] unless variables.empty?
      end

      # Returns a table's primary key and belonging sequence.
      def pk_and_sequence_for(table)
        execute_and_free("SHOW CREATE TABLE #{quote_table_name(table)}", 'SCHEMA') do |result|
          create_table = each_hash(result).first[:"Create Table"]
          if create_table.to_s =~ /PRIMARY KEY\s+(?:USING\s+\w+\s+)?\((.+)\)/
            keys = $1.split(",").map { |key| key.gsub(/[`"]/, "") }
            keys.length == 1 ? [keys.first, nil] : nil
          else
            nil
          end
        end
      end

      # Returns just a table's primary key
      def primary_key(table)
        pk_and_sequence = pk_and_sequence_for(table)
        pk_and_sequence && pk_and_sequence.first
      end

      def case_sensitive_modifier(node)
        Arel::Nodes::Bin.new(node)
      end

      def case_insensitive_comparison(table, attribute, column, value)
        if column.case_sensitive?
          super
        else
          table[attribute].eq(value)
        end
      end

      def limited_update_conditions(where_sql, quoted_table_name, quoted_primary_key)
        where_sql
      end

      protected

      def add_index_length(option_strings, column_names, options = {})
        if options.is_a?(Hash) && length = options[:length]
          case length
          when Hash
            column_names.each {|name| option_strings[name] += "(#{length[name]})" if length.has_key?(name) && length[name].present?}
          when Fixnum
            column_names.each {|name| option_strings[name] += "(#{length})"}
          end
        end

        return option_strings
      end

      def quoted_columns_for_index(column_names, options = {})
        option_strings = Hash[column_names.map {|name| [name, '']}]

        # add index length
        option_strings = add_index_length(option_strings, column_names, options)

        # add index sort order
        option_strings = add_index_sort_order(option_strings, column_names, options)

        column_names.map {|name| quote_column_name(name) + option_strings[name]}
      end

      def translate_exception(exception, message)
        case error_number(exception)
        when 1062
          RecordNotUnique.new(message, exception)
        when 1452
          InvalidForeignKey.new(message, exception)
        else
          super
        end
      end

      def add_column_sql(table_name, column_name, type, options = {})
        add_column_sql = "ADD #{quote_column_name(column_name)} #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"
        add_column_options!(add_column_sql, options)
        add_column_position!(add_column_sql, options)
        add_column_sql
      end

      def change_column_sql(table_name, column_name, type, options = {})
        column = column_for(table_name, column_name)

        unless options_include_default?(options)
          options[:default] = column.default
        end

        unless options.has_key?(:null)
          options[:null] = column.null
        end

        change_column_sql = "CHANGE #{quote_column_name(column_name)} #{quote_column_name(column_name)} #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"
        add_column_options!(change_column_sql, options)
        add_column_position!(change_column_sql, options)
        change_column_sql
      end

      def rename_column_sql(table_name, column_name, new_column_name)
        options = {}

        if column = columns(table_name).find { |c| c.name == column_name.to_s }
          options[:default] = column.default
          options[:null] = column.null
        else
          raise ActiveRecordError, "No such column: #{table_name}.#{column_name}"
        end

        current_type = select_one("SHOW COLUMNS FROM #{quote_table_name(table_name)} LIKE '#{column_name}'")["Type"]
        rename_column_sql = "CHANGE #{quote_column_name(column_name)} #{quote_column_name(new_column_name)} #{current_type}"
        add_column_options!(rename_column_sql, options)
        rename_column_sql
      end

      def remove_column_sql(table_name, *column_names)
        columns_for_remove(table_name, *column_names).map {|column_name| "DROP #{column_name}" }
      end
      alias :remove_columns_sql :remove_column

      def add_index_sql(table_name, column_name, options = {})
        index_name, index_type, index_columns = add_index_options(table_name, column_name, options)
        "ADD #{index_type} INDEX #{index_name} (#{index_columns})"
      end

      def remove_index_sql(table_name, options = {})
        index_name = index_name_for_remove(table_name, options)
        "DROP INDEX #{index_name}"
      end

      def add_timestamps_sql(table_name)
        [add_column_sql(table_name, :created_at, :datetime), add_column_sql(table_name, :updated_at, :datetime)]
      end

      def remove_timestamps_sql(table_name)
        [remove_column_sql(table_name, :updated_at), remove_column_sql(table_name, :created_at)]
      end

      private

      def supports_views?
        version[0] >= 5
      end

      def column_for(table_name, column_name)
        unless column = columns(table_name).find { |c| c.name == column_name.to_s }
          raise "No such column: #{table_name}.#{column_name}"
        end
        column
      end
    end
  end
end
require 'set'

module ActiveRecord
  # :stopdoc:
  module ConnectionAdapters
    # An abstract definition of a column in a table.
    class Column
      TRUE_VALUES = [true, 1, '1', 't', 'T', 'true', 'TRUE', 'on', 'ON'].to_set
      FALSE_VALUES = [false, 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF'].to_set

      module Format
        ISO_DATE = /\A(\d{4})-(\d\d)-(\d\d)\z/
        ISO_DATETIME = /\A(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(\.\d+)?\z/
      end

      attr_reader :name, :default, :type, :limit, :null, :sql_type, :precision, :scale
      attr_accessor :primary, :coder

      alias :encoded? :coder

      # Instantiates a new column in the table.
      #
      # +name+ is the column's name, such as <tt>supplier_id</tt> in <tt>supplier_id int(11)</tt>.
      # +default+ is the type-casted default value, such as +new+ in <tt>sales_stage varchar(20) default 'new'</tt>.
      # +sql_type+ is used to extract the column's length, if necessary. For example +60+ in
      # <tt>company_name varchar(60)</tt>.
      # It will be mapped to one of the standard Rails SQL types in the <tt>type</tt> attribute.
      # +null+ determines if this column allows +NULL+ values.
      def initialize(name, default, sql_type = nil, null = true)
        @name      = name
        @sql_type  = sql_type
        @null      = null
        @limit     = extract_limit(sql_type)
        @precision = extract_precision(sql_type)
        @scale     = extract_scale(sql_type)
        @type      = simplified_type(sql_type)
        @default   = extract_default(default)
        @primary   = nil
        @coder     = nil
      end

      # Returns +true+ if the column is either of type string or text.
      def text?
        type == :string || type == :text
      end

      # Returns +true+ if the column is either of type integer, float or decimal.
      def number?
        type == :integer || type == :float || type == :decimal
      end

      def has_default?
        !default.nil?
      end

      # Returns the Ruby class that corresponds to the abstract data type.
      def klass
        case type
        when :integer                     then Fixnum
        when :float                       then Float
        when :decimal                     then BigDecimal
        when :datetime, :timestamp, :time then Time
        when :date                        then Date
        when :text, :string, :binary      then String
        when :boolean                     then Object
        end
      end

      # Casts value (which is a String) to an appropriate instance.
      def type_cast(value)
        return nil if value.nil?
        return coder.load(value) if encoded?

        klass = self.class

        case type
        when :string, :text        then value
        when :integer              then klass.value_to_integer(value)
        when :float                then value.to_f
        when :decimal              then klass.value_to_decimal(value)
        when :datetime, :timestamp then klass.string_to_time(value)
        when :time                 then klass.string_to_dummy_time(value)
        when :date                 then klass.string_to_date(value)
        when :binary               then klass.binary_to_string(value)
        when :boolean              then klass.value_to_boolean(value)
        else value
        end
      end

      def type_cast_code(var_name)
        klass = self.class.name

        case type
        when :string, :text        then var_name
        when :integer              then "#{klass}.value_to_integer(#{var_name})"
        when :float                then "#{var_name}.to_f"
        when :decimal              then "#{klass}.value_to_decimal(#{var_name})"
        when :datetime, :timestamp then "#{klass}.string_to_time(#{var_name})"
        when :time                 then "#{klass}.string_to_dummy_time(#{var_name})"
        when :date                 then "#{klass}.string_to_date(#{var_name})"
        when :binary               then "#{klass}.binary_to_string(#{var_name})"
        when :boolean              then "#{klass}.value_to_boolean(#{var_name})"
        else var_name
        end
      end

      # Returns the human name of the column name.
      #
      # ===== Examples
      #  Column.new('sales_stage', ...).human_name # => 'Sales stage'
      def human_name
        Base.human_attribute_name(@name)
      end

      def extract_default(default)
        type_cast(default)
      end

      # Used to convert from Strings to BLOBs
      def string_to_binary(value)
        self.class.string_to_binary(value)
      end

      class << self
        # Used to convert from Strings to BLOBs
        def string_to_binary(value)
          value
        end

        # Used to convert from BLOBs to Strings
        def binary_to_string(value)
          value
        end

        def string_to_date(string)
          return string unless string.is_a?(String)
          return nil if string.empty?

          fast_string_to_date(string) || fallback_string_to_date(string)
        end

        def string_to_time(string)
          return string unless string.is_a?(String)
          return nil if string.empty?

          fast_string_to_time(string) || fallback_string_to_time(string)
        end

        def string_to_dummy_time(string)
          return string unless string.is_a?(String)
          return nil if string.empty?

          dummy_time_string = "2000-01-01 #{string}"

          fast_string_to_time(dummy_time_string) || begin
            time_hash = Date._parse(dummy_time_string)
            return nil if time_hash[:hour].nil?
            new_time(*time_hash.values_at(:year, :mon, :mday, :hour, :min, :sec, :sec_fraction))
          end
        end

        # convert something to a boolean
        def value_to_boolean(value)
          if value.is_a?(String) && value.blank?
            nil
          else
            TRUE_VALUES.include?(value)
          end
        end

        # Used to convert values to integer.
        # handle the case when an integer column is used to store boolean values
        def value_to_integer(value)
          case value
          when TrueClass, FalseClass
            value ? 1 : 0
          else
            value.to_i
          end
        end

        # convert something to a BigDecimal
        def value_to_decimal(value)
          # Using .class is faster than .is_a? and
          # subclasses of BigDecimal will be handled
          # in the else clause
          if value.class == BigDecimal
            value
          elsif value.respond_to?(:to_d)
            value.to_d
          else
            value.to_s.to_d
          end
        end

        protected
          # '0.123456' -> 123456
          # '1.123456' -> 123456
          def microseconds(time)
            time[:sec_fraction] ? (time[:sec_fraction] * 1_000_000).to_i : 0
          end

          def new_date(year, mon, mday)
            if year && year != 0
              Date.new(year, mon, mday) rescue nil
            end
          end

          def new_time(year, mon, mday, hour, min, sec, microsec)
            # Treat 0000-00-00 00:00:00 as nil.
            return nil if year.nil? || (year == 0 && mon == 0 && mday == 0)

            Time.time_with_datetime_fallback(Base.default_timezone, year, mon, mday, hour, min, sec, microsec) rescue nil
          end

          def fast_string_to_date(string)
            if string =~ Format::ISO_DATE
              new_date $1.to_i, $2.to_i, $3.to_i
            end
          end

          if RUBY_VERSION >= '1.9'
            # Doesn't handle time zones.
            def fast_string_to_time(string)
              if string =~ Format::ISO_DATETIME
                microsec = ($7.to_r * 1_000_000).to_i
                new_time $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i, microsec
              end
            end
          else
            def fast_string_to_time(string)
              if string =~ Format::ISO_DATETIME
                microsec = ($7.to_f * 1_000_000).round.to_i
                new_time $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i, microsec
              end
            end
          end

          def fallback_string_to_date(string)
            new_date(*::Date._parse(string, false).values_at(:year, :mon, :mday))
          end

          def fallback_string_to_time(string)
            time_hash = Date._parse(string)
            time_hash[:sec_fraction] = microseconds(time_hash)

            new_time(*time_hash.values_at(:year, :mon, :mday, :hour, :min, :sec, :sec_fraction))
          end
      end

      private
        def extract_limit(sql_type)
          $1.to_i if sql_type =~ /\((.*)\)/
        end

        def extract_precision(sql_type)
          $2.to_i if sql_type =~ /^(numeric|decimal|number)\((\d+)(,\d+)?\)/i
        end

        def extract_scale(sql_type)
          case sql_type
            when /^(numeric|decimal|number)\((\d+)\)/i then 0
            when /^(numeric|decimal|number)\((\d+)(,(\d+))\)/i then $4.to_i
          end
        end

        def simplified_type(field_type)
          case field_type
          when /int/i
            :integer
          when /float|double/i
            :float
          when /decimal|numeric|number/i
            extract_scale(field_type) == 0 ? :integer : :decimal
          when /datetime/i
            :datetime
          when /timestamp/i
            :timestamp
          when /time/i
            :time
          when /date/i
            :date
          when /clob/i, /text/i
            :text
          when /blob/i, /binary/i
            :binary
          when /char/i, /string/i
            :string
          when /boolean/i
            :boolean
          end
        end
    end
  end
  # :startdoc:
end
require 'active_record/connection_adapters/abstract_mysql_adapter'

gem 'mysql2', '~> 0.3.10'
require 'mysql2'

module ActiveRecord
  class Base
    # Establishes a connection to the database that's used by all Active Record objects.
    def self.mysql2_connection(config)
      config[:username] = 'root' if config[:username].nil?

      if Mysql2::Client.const_defined? :FOUND_ROWS
        config[:flags] = Mysql2::Client::FOUND_ROWS
      end

      client = Mysql2::Client.new(config.symbolize_keys)
      options = [config[:host], config[:username], config[:password], config[:database], config[:port], config[:socket], 0]
      ConnectionAdapters::Mysql2Adapter.new(client, logger, options, config)
    end
  end

  module ConnectionAdapters
    class Mysql2Adapter < AbstractMysqlAdapter

      class Column < AbstractMysqlAdapter::Column # :nodoc:
        def adapter
          Mysql2Adapter
        end
      end

      ADAPTER_NAME = 'Mysql2'

      def initialize(connection, logger, connection_options, config)
        super
        @visitor = BindSubstitution.new self
        configure_connection
      end

      def supports_explain?
        true
      end

      # HELPER METHODS ===========================================

      def each_hash(result) # :nodoc:
        if block_given?
          result.each(:as => :hash, :symbolize_keys => true) do |row|
            yield row
          end
        else
          to_enum(:each_hash, result)
        end
      end

      def new_column(field, default, type, null, collation) # :nodoc:
        Column.new(field, default, type, null, collation)
      end

      def error_number(exception)
        exception.error_number if exception.respond_to?(:error_number)
      end

      # QUOTING ==================================================

      def quote_string(string)
        @connection.escape(string)
      end

      # CONNECTION MANAGEMENT ====================================

      def active?
        return false unless @connection
        @connection.ping
      end

      def reconnect!
        disconnect!
        connect
      end

      # Disconnects from the database if already connected.
      # Otherwise, this method does nothing.
      def disconnect!
        unless @connection.nil?
          @connection.close
          @connection = nil
        end
      end

      def reset!
        disconnect!
        connect
      end

      # DATABASE STATEMENTS ======================================

      def explain(arel, binds = [])
        sql     = "EXPLAIN #{to_sql(arel, binds.dup)}"
        start   = Time.now
        result  = exec_query(sql, 'EXPLAIN', binds)
        elapsed = Time.now - start

        ExplainPrettyPrinter.new.pp(result, elapsed)
      end

      class ExplainPrettyPrinter # :nodoc:
        # Pretty prints the result of a EXPLAIN in a way that resembles the output of the
        # MySQL shell:
        #
        #   +----+-------------+-------+-------+---------------+---------+---------+-------+------+-------------+
        #   | id | select_type | table | type  | possible_keys | key     | key_len | ref   | rows | Extra       |
        #   +----+-------------+-------+-------+---------------+---------+---------+-------+------+-------------+
        #   |  1 | SIMPLE      | users | const | PRIMARY       | PRIMARY | 4       | const |    1 |             |
        #   |  1 | SIMPLE      | posts | ALL   | NULL          | NULL    | NULL    | NULL  |    1 | Using where |
        #   +----+-------------+-------+-------+---------------+---------+---------+-------+------+-------------+
        #   2 rows in set (0.00 sec)
        #
        # This is an exercise in Ruby hyperrealism :).
        def pp(result, elapsed)
          widths    = compute_column_widths(result)
          separator = build_separator(widths)

          pp = []

          pp << separator
          pp << build_cells(result.columns, widths)
          pp << separator

          result.rows.each do |row|
            pp << build_cells(row, widths)
          end

          pp << separator
          pp << build_footer(result.rows.length, elapsed)

          pp.join("\n") + "\n"
        end

        private

        def compute_column_widths(result)
          [].tap do |widths|
            result.columns.each_with_index do |column, i|
              cells_in_column = [column] + result.rows.map {|r| r[i].nil? ? 'NULL' : r[i].to_s}
              widths << cells_in_column.map(&:length).max
            end
          end
        end

        def build_separator(widths)
          padding = 1
          '+' + widths.map {|w| '-' * (w + (padding*2))}.join('+') + '+'
        end

        def build_cells(items, widths)
          cells = []
          items.each_with_index do |item, i|
            item = 'NULL' if item.nil?
            justifier = item.is_a?(Numeric) ? 'rjust' : 'ljust'
            cells << item.to_s.send(justifier, widths[i])
          end
          '| ' + cells.join(' | ') + ' |'
        end

        def build_footer(nrows, elapsed)
          rows_label = nrows == 1 ? 'row' : 'rows'
          "#{nrows} #{rows_label} in set (%.2f sec)" % elapsed
        end
      end

      # FIXME: re-enable the following once a "better" query_cache solution is in core
      #
      # The overrides below perform much better than the originals in AbstractAdapter
      # because we're able to take advantage of mysql2's lazy-loading capabilities
      #
      # # Returns a record hash with the column names as keys and column values
      # # as values.
      # def select_one(sql, name = nil)
      #   result = execute(sql, name)
      #   result.each(:as => :hash) do |r|
      #     return r
      #   end
      # end
      #
      # # Returns a single value from a record
      # def select_value(sql, name = nil)
      #   result = execute(sql, name)
      #   if first = result.first
      #     first.first
      #   end
      # end
      #
      # # Returns an array of the values of the first column in a select:
      # #   select_values("SELECT id FROM companies LIMIT 3") => [1,2,3]
      # def select_values(sql, name = nil)
      #   execute(sql, name).map { |row| row.first }
      # end

      # Returns an array of arrays containing the field values.
      # Order is the same as that returned by +columns+.
      def select_rows(sql, name = nil)
        execute(sql, name).to_a
      end

      # Executes the SQL statement in the context of this connection.
      def execute(sql, name = nil)
        # make sure we carry over any changes to ActiveRecord::Base.default_timezone that have been
        # made since we established the connection
        @connection.query_options[:database_timezone] = ActiveRecord::Base.default_timezone

        super
      end

      def exec_query(sql, name = 'SQL', binds = [])
        result = execute(sql, name)
        ActiveRecord::Result.new(result.fields, result.to_a)
      end

      alias exec_without_stmt exec_query

      # Returns an array of record hashes with the column names as keys and
      # column values as values.
      def select(sql, name = nil, binds = [])
        exec_query(sql, name).to_a
      end

      def insert_sql(sql, name = nil, pk = nil, id_value = nil, sequence_name = nil)
        super
        id_value || @connection.last_id
      end
      alias :create :insert_sql

      def exec_insert(sql, name, binds)
        execute to_sql(sql, binds), name
      end

      def exec_delete(sql, name, binds)
        execute to_sql(sql, binds), name
        @connection.affected_rows
      end
      alias :exec_update :exec_delete

      def last_inserted_id(result)
        @connection.last_id
      end

      private

      def connect
        @connection = Mysql2::Client.new(@config)
        configure_connection
      end

      def configure_connection
        @connection.query_options.merge!(:as => :array)

        # By default, MySQL 'where id is null' selects the last inserted id.
        # Turn this off. http://dev.rubyonrails.org/ticket/6778
        variable_assignments = ['SQL_AUTO_IS_NULL=0']
        encoding = @config[:encoding]

        # make sure we set the encoding
        variable_assignments << "NAMES '#{encoding}'" if encoding

        # increase timeout so mysql server doesn't disconnect us
        wait_timeout = @config[:wait_timeout]
        wait_timeout = 2147483 unless wait_timeout.is_a?(Fixnum)
        variable_assignments << "@@wait_timeout = #{wait_timeout}"

        execute("SET #{variable_assignments.join(', ')}", :skip_logging)
      end

      def version
        @version ||= @connection.info[:version].scan(/^(\d+)\.(\d+)\.(\d+)/).flatten.map { |v| v.to_i }
      end
    end
  end
end
require 'active_record/connection_adapters/abstract_mysql_adapter'
require 'active_record/connection_adapters/statement_pool'
require 'active_support/core_ext/hash/keys'

gem 'mysql', '~> 2.8.1'
require 'mysql'

class Mysql
  class Time
    ###
    # This monkey patch is for test_additional_columns_from_join_table
    def to_date
      Date.new(year, month, day)
    end
  end
  class Stmt; include Enumerable end
  class Result; include Enumerable end
end

module ActiveRecord
  class Base
    # Establishes a connection to the database that's used by all Active Record objects.
    def self.mysql_connection(config) # :nodoc:
      config = config.symbolize_keys
      host     = config[:host]
      port     = config[:port]
      socket   = config[:socket]
      username = config[:username] ? config[:username].to_s : 'root'
      password = config[:password].to_s
      database = config[:database]

      mysql = Mysql.init
      mysql.ssl_set(config[:sslkey], config[:sslcert], config[:sslca], config[:sslcapath], config[:sslcipher]) if config[:sslca] || config[:sslkey]

      default_flags = Mysql.const_defined?(:CLIENT_MULTI_RESULTS) ? Mysql::CLIENT_MULTI_RESULTS : 0
      default_flags |= Mysql::CLIENT_FOUND_ROWS if Mysql.const_defined?(:CLIENT_FOUND_ROWS)
      options = [host, username, password, database, port, socket, default_flags]
      ConnectionAdapters::MysqlAdapter.new(mysql, logger, options, config)
    end
  end

  module ConnectionAdapters
    # The MySQL adapter will work with both Ruby/MySQL, which is a Ruby-based MySQL adapter that comes bundled with Active Record, and with
    # the faster C-based MySQL/Ruby adapter (available both as a gem and from http://www.tmtm.org/en/mysql/ruby/).
    #
    # Options:
    #
    # * <tt>:host</tt> - Defaults to "localhost".
    # * <tt>:port</tt> - Defaults to 3306.
    # * <tt>:socket</tt> - Defaults to "/tmp/mysql.sock".
    # * <tt>:username</tt> - Defaults to "root"
    # * <tt>:password</tt> - Defaults to nothing.
    # * <tt>:database</tt> - The name of the database. No default, must be provided.
    # * <tt>:encoding</tt> - (Optional) Sets the client encoding by executing "SET NAMES <encoding>" after connection.
    # * <tt>:reconnect</tt> - Defaults to false (See MySQL documentation: http://dev.mysql.com/doc/refman/5.0/en/auto-reconnect.html).
    # * <tt>:sslca</tt> - Necessary to use MySQL with an SSL connection.
    # * <tt>:sslkey</tt> - Necessary to use MySQL with an SSL connection.
    # * <tt>:sslcert</tt> - Necessary to use MySQL with an SSL connection.
    # * <tt>:sslcapath</tt> - Necessary to use MySQL with an SSL connection.
    # * <tt>:sslcipher</tt> - Necessary to use MySQL with an SSL connection.
    #
    class MysqlAdapter < AbstractMysqlAdapter

      class Column < AbstractMysqlAdapter::Column #:nodoc:
        def self.string_to_time(value)
          return super unless Mysql::Time === value
          new_time(
            value.year,
            value.month,
            value.day,
            value.hour,
            value.minute,
            value.second,
            value.second_part)
        end

        def self.string_to_dummy_time(v)
          return super unless Mysql::Time === v
          new_time(2000, 01, 01, v.hour, v.minute, v.second, v.second_part)
        end

        def self.string_to_date(v)
          return super unless Mysql::Time === v
          new_date(v.year, v.month, v.day)
        end

        def adapter
          MysqlAdapter
        end
      end

      ADAPTER_NAME = 'MySQL'

      class StatementPool < ConnectionAdapters::StatementPool
        def initialize(connection, max = 1000)
          super
          @cache = Hash.new { |h,pid| h[pid] = {} }
        end

        def each(&block); cache.each(&block); end
        def key?(key);    cache.key?(key); end
        def [](key);      cache[key]; end
        def length;       cache.length; end
        def delete(key);  cache.delete(key); end

        def []=(sql, key)
          while @max <= cache.size
            cache.shift.last[:stmt].close
          end
          cache[sql] = key
        end

        def clear
          cache.values.each do |hash|
            hash[:stmt].close
          end
          cache.clear
        end

        private
        def cache
          @cache[$$]
        end
      end

      def initialize(connection, logger, connection_options, config)
        super
        @statements = StatementPool.new(@connection,
                                        config.fetch(:statement_limit) { 1000 })
        @client_encoding = nil
        connect
      end

      # Returns true, since this connection adapter supports prepared statement
      # caching.
      def supports_statement_cache?
        true
      end

      # HELPER METHODS ===========================================

      def each_hash(result) # :nodoc:
        if block_given?
          result.each_hash do |row|
            row.symbolize_keys!
            yield row
          end
        else
          to_enum(:each_hash, result)
        end
      end

      def new_column(field, default, type, null, collation) # :nodoc:
        Column.new(field, default, type, null, collation)
      end

      def error_number(exception) # :nodoc:
        exception.errno if exception.respond_to?(:errno)
      end

      # QUOTING ==================================================

      def type_cast(value, column)
        return super unless value == true || value == false

        value ? 1 : 0
      end

      def quote_string(string) #:nodoc:
        @connection.quote(string)
      end

      # CONNECTION MANAGEMENT ====================================

      def active?
        if @connection.respond_to?(:stat)
          @connection.stat
        else
          @connection.query 'select 1'
        end

        # mysql-ruby doesn't raise an exception when stat fails.
        if @connection.respond_to?(:errno)
          @connection.errno.zero?
        else
          true
        end
      rescue Mysql::Error
        false
      end

      def reconnect!
        disconnect!
        clear_cache!
        connect
      end

      # Disconnects from the database if already connected. Otherwise, this
      # method does nothing.
      def disconnect!
        @connection.close rescue nil
      end

      def reset!
        if @connection.respond_to?(:change_user)
          # See http://bugs.mysql.com/bug.php?id=33540 -- the workaround way to
          # reset the connection is to change the user to the same user.
          @connection.change_user(@config[:username], @config[:password], @config[:database])
          configure_connection
        end
      end

      # DATABASE STATEMENTS ======================================

      def select_rows(sql, name = nil)
        @connection.query_with_result = true
        rows = exec_query(sql, name).rows
        @connection.more_results && @connection.next_result    # invoking stored procedures with CLIENT_MULTI_RESULTS requires this to tidy up else connection will be dropped
        rows
      end

      # Clears the prepared statements cache.
      def clear_cache!
        @statements.clear
      end

      if "<3".respond_to?(:encode)
        # Taken from here:
        #   https://github.com/tmtm/ruby-mysql/blob/master/lib/mysql/charset.rb
        # Author: TOMITA Masahiro <tommy@tmtm.org>
        ENCODINGS = {
          "armscii8" => nil,
          "ascii"    => Encoding::US_ASCII,
          "big5"     => Encoding::Big5,
          "binary"   => Encoding::ASCII_8BIT,
          "cp1250"   => Encoding::Windows_1250,
          "cp1251"   => Encoding::Windows_1251,
          "cp1256"   => Encoding::Windows_1256,
          "cp1257"   => Encoding::Windows_1257,
          "cp850"    => Encoding::CP850,
          "cp852"    => Encoding::CP852,
          "cp866"    => Encoding::IBM866,
          "cp932"    => Encoding::Windows_31J,
          "dec8"     => nil,
          "eucjpms"  => Encoding::EucJP_ms,
          "euckr"    => Encoding::EUC_KR,
          "gb2312"   => Encoding::EUC_CN,
          "gbk"      => Encoding::GBK,
          "geostd8"  => nil,
          "greek"    => Encoding::ISO_8859_7,
          "hebrew"   => Encoding::ISO_8859_8,
          "hp8"      => nil,
          "keybcs2"  => nil,
          "koi8r"    => Encoding::KOI8_R,
          "koi8u"    => Encoding::KOI8_U,
          "latin1"   => Encoding::ISO_8859_1,
          "latin2"   => Encoding::ISO_8859_2,
          "latin5"   => Encoding::ISO_8859_9,
          "latin7"   => Encoding::ISO_8859_13,
          "macce"    => Encoding::MacCentEuro,
          "macroman" => Encoding::MacRoman,
          "sjis"     => Encoding::SHIFT_JIS,
          "swe7"     => nil,
          "tis620"   => Encoding::TIS_620,
          "ucs2"     => Encoding::UTF_16BE,
          "ujis"     => Encoding::EucJP_ms,
          "utf8"     => Encoding::UTF_8,
          "utf8mb4"  => Encoding::UTF_8,
        }
      else
        ENCODINGS = Hash.new { |h,k| h[k] = k }
      end

      # Get the client encoding for this database
      def client_encoding
        return @client_encoding if @client_encoding

        result = exec_query(
          "SHOW VARIABLES WHERE Variable_name = 'character_set_client'",
          'SCHEMA')
        @client_encoding = ENCODINGS[result.rows.last.last]
      end

      def exec_query(sql, name = 'SQL', binds = [])
        # If the configuration sets prepared_statements:false, binds will
        # always be empty, since the bind variables will have been already
        # substituted and removed from binds by BindVisitor, so this will
        # effectively disable prepared statement usage completely.
        if binds.empty?
          result_set, affected_rows = exec_without_stmt(sql, name)
        else
          result_set, affected_rows = exec_stmt(sql, name, binds)
        end

        yield affected_rows if block_given?

        result_set
      end

      def last_inserted_id(result)
        @connection.insert_id
      end

      def exec_without_stmt(sql, name = 'SQL') # :nodoc:
        # Some queries, like SHOW CREATE TABLE don't work through the prepared
        # statement API. For those queries, we need to use this method. :'(
        log(sql, name) do
          result = @connection.query(sql)
          affected_rows = @connection.affected_rows

          if result
            cols = result.fetch_fields.map { |field| field.name }
            result_set = ActiveRecord::Result.new(cols, result.to_a)
            result.free
          else
            result_set = ActiveRecord::Result.new([], [])
          end

          [result_set, affected_rows]
        end
      end

      def execute_and_free(sql, name = nil)
        result = execute(sql, name)
        ret = yield result
        result.free
        ret
      end

      def insert_sql(sql, name = nil, pk = nil, id_value = nil, sequence_name = nil) #:nodoc:
        super sql, name
        id_value || @connection.insert_id
      end
      alias :create :insert_sql

      def exec_delete(sql, name, binds)
        affected_rows = 0

        exec_query(sql, name, binds) do |n|
          affected_rows = n
        end

        affected_rows
      end
      alias :exec_update :exec_delete

      def begin_db_transaction #:nodoc:
        exec_query "BEGIN"
      rescue Mysql::Error
        # Transactions aren't supported
      end

      private

      def exec_stmt(sql, name, binds)
        cache = {}
        log(sql, name, binds) do
          if binds.empty?
            stmt = @connection.prepare(sql)
          else
            cache = @statements[sql] ||= {
              :stmt => @connection.prepare(sql)
            }
            stmt = cache[:stmt]
          end

          begin
            stmt.execute(*binds.map { |col, val| type_cast(val, col) })
          rescue Mysql::Error => e
            # Older versions of MySQL leave the prepared statement in a bad
            # place when an error occurs. To support older mysql versions, we
            # need to close the statement and delete the statement from the
            # cache.
            stmt.close
            @statements.delete sql
            raise e
          end

          cols = nil
          if metadata = stmt.result_metadata
            cols = cache[:cols] ||= metadata.fetch_fields.map { |field|
              field.name
            }
          end

          result_set = ActiveRecord::Result.new(cols, stmt.to_a) if cols
          affected_rows = stmt.affected_rows

          stmt.result_metadata.free if cols
          stmt.free_result
          stmt.close if binds.empty?

          [result_set, affected_rows]
        end
      end

      def connect
        encoding = @config[:encoding]
        if encoding
          @connection.options(Mysql::SET_CHARSET_NAME, encoding) rescue nil
        end

        if @config[:sslca] || @config[:sslkey]
          @connection.ssl_set(@config[:sslkey], @config[:sslcert], @config[:sslca], @config[:sslcapath], @config[:sslcipher])
        end

        @connection.options(Mysql::OPT_CONNECT_TIMEOUT, @config[:connect_timeout]) if @config[:connect_timeout]
        @connection.options(Mysql::OPT_READ_TIMEOUT, @config[:read_timeout]) if @config[:read_timeout]
        @connection.options(Mysql::OPT_WRITE_TIMEOUT, @config[:write_timeout]) if @config[:write_timeout]

        @connection.real_connect(*@connection_options)

        # reconnect must be set after real_connect is called, because real_connect sets it to false internally
        @connection.reconnect = !!@config[:reconnect] if @connection.respond_to?(:reconnect=)

        configure_connection
      end

      def configure_connection
        encoding = @config[:encoding]
        execute("SET NAMES '#{encoding}'", :skip_logging) if encoding

        # By default, MySQL 'where id is null' selects the last inserted id.
        # Turn this off. http://dev.rubyonrails.org/ticket/6778
        execute("SET SQL_AUTO_IS_NULL=0", :skip_logging)
      end

      def select(sql, name = nil, binds = [])
        @connection.query_with_result = true
        rows = exec_query(sql, name, binds).to_a
        @connection.more_results && @connection.next_result    # invoking stored procedures with CLIENT_MULTI_RESULTS requires this to tidy up else connection will be dropped
        rows
      end

      # Returns the version of the connected MySQL server.
      def version
        @version ||= @connection.server_info.scan(/^(\d+)\.(\d+)\.(\d+)/).flatten.map { |v| v.to_i }
      end
    end
  end
end
require 'active_record/connection_adapters/abstract_adapter'
require 'active_support/core_ext/object/blank'
require 'active_record/connection_adapters/statement_pool'
require 'arel/visitors/bind_visitor'

# Make sure we're using pg high enough for PGResult#values
gem 'pg', '~> 0.11'
require 'pg'

module ActiveRecord
  class Base
    # Establishes a connection to the database that's used by all Active Record objects
    def self.postgresql_connection(config) # :nodoc:
      config = config.symbolize_keys
      host     = config[:host]
      port     = config[:port] || 5432
      username = config[:username].to_s if config[:username]
      password = config[:password].to_s if config[:password]

      if config.key?(:database)
        database = config[:database]
      else
        raise ArgumentError, "No database specified. Missing argument: database."
      end

      # The postgres drivers don't allow the creation of an unconnected PGconn object,
      # so just pass a nil connection object for the time being.
      ConnectionAdapters::PostgreSQLAdapter.new(nil, logger, [host, port, nil, nil, database, username, password], config)
    end
  end

  module ConnectionAdapters
    # PostgreSQL-specific extensions to column definitions in a table.
    class PostgreSQLColumn < Column #:nodoc:
      # Instantiates a new PostgreSQL column definition in a table.
      def initialize(name, default, sql_type = nil, null = true)
        super(name, self.class.extract_value_from_default(default), sql_type, null)
      end

      # :stopdoc:
      class << self
        attr_accessor :money_precision
        def string_to_time(string)
          return string unless String === string

          case string
          when 'infinity'  then 1.0 / 0.0
          when '-infinity' then -1.0 / 0.0
          else
            super
          end
        end
      end
      # :startdoc:

      private
        def extract_limit(sql_type)
          case sql_type
          when /^bigint/i;    8
          when /^smallint/i;  2
          else super
          end
        end

        # Extracts the scale from PostgreSQL-specific data types.
        def extract_scale(sql_type)
          # Money type has a fixed scale of 2.
          sql_type =~ /^money/ ? 2 : super
        end

        # Extracts the precision from PostgreSQL-specific data types.
        def extract_precision(sql_type)
          if sql_type == 'money'
            self.class.money_precision
          else
            super
          end
        end

        # Maps PostgreSQL-specific data types to logical Rails types.
        def simplified_type(field_type)
          case field_type
            # Numeric and monetary types
            when /^(?:real|double precision)$/
              :float
            # Monetary types
            when 'money'
              :decimal
            # Character types
            when /^(?:character varying|bpchar)(?:\(\d+\))?$/
              :string
            # Binary data types
            when 'bytea'
              :binary
            # Date/time types
            when /^timestamp with(?:out)? time zone$/
              :datetime
            when 'interval'
              :string
            # Geometric types
            when /^(?:point|line|lseg|box|"?path"?|polygon|circle)$/
              :string
            # Network address types
            when /^(?:cidr|inet|macaddr)$/
              :string
            # Bit strings
            when /^bit(?: varying)?(?:\(\d+\))?$/
              :string
            # XML type
            when 'xml'
              :xml
            # tsvector type
            when 'tsvector'
              :tsvector
            # Arrays
            when /^\D+\[\]$/
              :string
            # Object identifier types
            when 'oid'
              :integer
            # UUID type
            when 'uuid'
              :string
            # Small and big integer types
            when /^(?:small|big)int$/
              :integer
            # Pass through all types that are not specific to PostgreSQL.
            else
              super
          end
        end

        # Extracts the value from a PostgreSQL column default definition.
        def self.extract_value_from_default(default)
          case default
            # This is a performance optimization for Ruby 1.9.2 in development.
            # If the value is nil, we return nil straight away without checking
            # the regular expressions. If we check each regular expression,
            # Regexp#=== will call NilClass#to_str, which will trigger
            # method_missing (defined by whiny nil in ActiveSupport) which
            # makes this method very very slow.
            when NilClass
              nil
            # Numeric types
            when /\A\(?(-?\d+(\.\d*)?\)?)\z/
              $1
            # Character types
            when /\A\(?'(.*)'::.*\b(?:character varying|bpchar|text)\z/m
              $1
            # Binary data types
            when /\A'(.*)'::bytea\z/m
              $1
            # Date/time types
            when /\A'(.+)'::(?:time(?:stamp)? with(?:out)? time zone|date)\z/
              $1
            when /\A'(.*)'::interval\z/
              $1
            # Boolean type
            when 'true'
              true
            when 'false'
              false
            # Geometric types
            when /\A'(.*)'::(?:point|line|lseg|box|"?path"?|polygon|circle)\z/
              $1
            # Network address types
            when /\A'(.*)'::(?:cidr|inet|macaddr)\z/
              $1
            # Bit string types
            when /\AB'(.*)'::"?bit(?: varying)?"?\z/
              $1
            # XML type
            when /\A'(.*)'::xml\z/m
              $1
            # Arrays
            when /\A'(.*)'::"?\D+"?\[\]\z/
              $1
            # Object identifier types
            when /\A-?\d+\z/
              $1
            else
              # Anything else is blank, some user type, or some function
              # and we can't know the value of that, so return nil.
              nil
          end
        end
    end

    # The PostgreSQL adapter works both with the native C (http://ruby.scripting.ca/postgres/) and the pure
    # Ruby (available both as gem and from http://rubyforge.org/frs/?group_id=234&release_id=1944) drivers.
    #
    # Options:
    #
    # * <tt>:host</tt> - Defaults to "localhost".
    # * <tt>:port</tt> - Defaults to 5432.
    # * <tt>:username</tt> - Defaults to nothing.
    # * <tt>:password</tt> - Defaults to nothing.
    # * <tt>:database</tt> - The name of the database. No default, must be provided.
    # * <tt>:schema_search_path</tt> - An optional schema search path for the connection given
    #   as a string of comma-separated schema names. This is backward-compatible with the <tt>:schema_order</tt> option.
    # * <tt>:encoding</tt> - An optional client encoding that is used in a <tt>SET client_encoding TO
    #   <encoding></tt> call on the connection.
    # * <tt>:min_messages</tt> - An optional client min messages that is used in a
    #   <tt>SET client_min_messages TO <min_messages></tt> call on the connection.
    class PostgreSQLAdapter < AbstractAdapter
      class TableDefinition < ActiveRecord::ConnectionAdapters::TableDefinition
        def xml(*args)
          options = args.extract_options!
          column(args[0], 'xml', options)
        end

        def tsvector(*args)
          options = args.extract_options!
          column(args[0], 'tsvector', options)
        end
      end

      ADAPTER_NAME = 'PostgreSQL'

      NATIVE_DATABASE_TYPES = {
        :primary_key => "serial primary key",
        :string      => { :name => "character varying", :limit => 255 },
        :text        => { :name => "text" },
        :integer     => { :name => "integer" },
        :float       => { :name => "float" },
        :decimal     => { :name => "decimal" },
        :datetime    => { :name => "timestamp" },
        :timestamp   => { :name => "timestamp" },
        :time        => { :name => "time" },
        :date        => { :name => "date" },
        :binary      => { :name => "bytea" },
        :boolean     => { :name => "boolean" },
        :xml         => { :name => "xml" },
        :tsvector    => { :name => "tsvector" }
      }

      # Returns 'PostgreSQL' as adapter name for identification purposes.
      def adapter_name
        ADAPTER_NAME
      end

      # Returns +true+, since this connection adapter supports prepared statement
      # caching.
      def supports_statement_cache?
        true
      end

      def supports_index_sort_order?
        true
      end

      class StatementPool < ConnectionAdapters::StatementPool
        def initialize(connection, max)
          super
          @counter = 0
          @cache   = Hash.new { |h,pid| h[pid] = {} }
        end

        def each(&block); cache.each(&block); end
        def key?(key);    cache.key?(key); end
        def [](key);      cache[key]; end
        def length;       cache.length; end

        def next_key
          "a#{@counter + 1}"
        end

        def []=(sql, key)
          while @max <= cache.size
            dealloc(cache.shift.last)
          end
          @counter += 1
          cache[sql] = key
        end

        def clear
          cache.each_value do |stmt_key|
            dealloc stmt_key
          end
          cache.clear
        end

        def delete(sql_key)
          dealloc cache[sql_key]
          cache.delete sql_key
        end

        private
        def cache
          @cache[$$]
        end

        def dealloc(key)
          @connection.query "DEALLOCATE #{key}" if connection_active?
        end

        def connection_active?
          @connection.status == PGconn::CONNECTION_OK
        rescue PGError
          false
        end
      end

      class BindSubstitution < Arel::Visitors::PostgreSQL # :nodoc:
        include Arel::Visitors::BindVisitor
      end

      # Initializes and connects a PostgreSQL adapter.
      def initialize(connection, logger, connection_parameters, config)
        super(connection, logger)

        if config.fetch(:prepared_statements) { true }
          @visitor = Arel::Visitors::PostgreSQL.new self
        else
          @visitor = BindSubstitution.new self
        end

        connection_parameters.delete :prepared_statements

        @connection_parameters, @config = connection_parameters, config

        # @local_tz is initialized as nil to avoid warnings when connect tries to use it
        @local_tz = nil
        @table_alias_length = nil

        connect
        @statements = StatementPool.new @connection,
                                        config.fetch(:statement_limit) { 1000 }

        if postgresql_version < 80200
          raise "Your version of PostgreSQL (#{postgresql_version}) is too old, please upgrade!"
        end

        @local_tz = execute('SHOW TIME ZONE', 'SCHEMA').first["TimeZone"]
      end

      # Clears the prepared statements cache.
      def clear_cache!
        @statements.clear
      end

      # Is this connection alive and ready for queries?
      def active?
        @connection.query 'SELECT 1'
        true
      rescue PGError
        false
      end

      # Close then reopen the connection.
      def reconnect!
        clear_cache!
        @connection.reset
        @open_transactions = 0
        configure_connection
      end

      def reset!
        clear_cache!
        super
      end

      # Disconnects from the database if already connected. Otherwise, this
      # method does nothing.
      def disconnect!
        clear_cache!
        @connection.close rescue nil
      end

      def native_database_types #:nodoc:
        NATIVE_DATABASE_TYPES
      end

      # Returns true, since this connection adapter supports migrations.
      def supports_migrations?
        true
      end

      # Does PostgreSQL support finding primary key on non-Active Record tables?
      def supports_primary_key? #:nodoc:
        true
      end

      # Enable standard-conforming strings if available.
      def set_standard_conforming_strings
        old, self.client_min_messages = client_min_messages, 'panic'
        execute('SET standard_conforming_strings = on', 'SCHEMA') rescue nil
      ensure
        self.client_min_messages = old
      end

      def supports_insert_with_returning?
        true
      end

      def supports_ddl_transactions?
        true
      end

      # Returns true, since this connection adapter supports savepoints.
      def supports_savepoints?
        true
      end

      # Returns true.
      def supports_explain?
        true
      end

      # Returns the configured supported identifier length supported by PostgreSQL
      def table_alias_length
        @table_alias_length ||= query('SHOW max_identifier_length')[0][0].to_i
      end

      # QUOTING ==================================================

      # Escapes binary strings for bytea input to the database.
      def escape_bytea(value)
        @connection.escape_bytea(value) if value
      end

      # Unescapes bytea output from a database to the binary string it represents.
      # NOTE: This is NOT an inverse of escape_bytea! This is only to be used
      #       on escaped binary output from database drive.
      def unescape_bytea(value)
        @connection.unescape_bytea(value) if value
      end

      # Quotes PostgreSQL-specific data types for SQL input.
      def quote(value, column = nil) #:nodoc:
        return super unless column

        case value
        when Float
          return super unless value.infinite? && column.type == :datetime
          "'#{value.to_s.downcase}'"
        when Numeric
          return super unless column.sql_type == 'money'
          # Not truly string input, so doesn't require (or allow) escape string syntax.
          "'#{value}'"
        when String
          case column.sql_type
          when 'bytea' then "'#{escape_bytea(value)}'"
          when 'xml'   then "xml '#{quote_string(value)}'"
          when /^bit/
            case value
            when /^[01]*$/      then "B'#{value}'" # Bit-string notation
            when /^[0-9A-F]*$/i then "X'#{value}'" # Hexadecimal notation
            end
          else
            super
          end
        else
          super
        end
      end

      def type_cast(value, column)
        return super unless column

        case value
        when String
          return super unless 'bytea' == column.sql_type
          { :value => value, :format => 1 }
        else
          super
        end
      end

      # Quotes strings for use in SQL input.
      def quote_string(s) #:nodoc:
        @connection.escape(s)
      end

      # Checks the following cases:
      #
      # - table_name
      # - "table.name"
      # - schema_name.table_name
      # - schema_name."table.name"
      # - "schema.name".table_name
      # - "schema.name"."table.name"
      def quote_table_name(name)
        schema, name_part = extract_pg_identifier_from_name(name.to_s)

        unless name_part
          quote_column_name(schema)
        else
          table_name, name_part = extract_pg_identifier_from_name(name_part)
          "#{quote_column_name(schema)}.#{quote_column_name(table_name)}"
        end
      end

      # Quotes column names for use in SQL queries.
      def quote_column_name(name) #:nodoc:
        PGconn.quote_ident(name.to_s)
      end

      # Quote date/time values for use in SQL input. Includes microseconds
      # if the value is a Time responding to usec.
      def quoted_date(value) #:nodoc:
        if value.acts_like?(:time) && value.respond_to?(:usec)
          "#{super}.#{sprintf("%06d", value.usec)}"
        else
          super
        end
      end

      # Set the authorized user for this session
      def session_auth=(user)
        clear_cache!
        exec_query "SET SESSION AUTHORIZATION #{user}"
      end

      # REFERENTIAL INTEGRITY ====================================

      def supports_disable_referential_integrity? #:nodoc:
        true
      end

      def disable_referential_integrity #:nodoc:
        if supports_disable_referential_integrity? then
          execute(tables.collect { |name| "ALTER TABLE #{quote_table_name(name)} DISABLE TRIGGER ALL" }.join(";"))
        end
        yield
      ensure
        if supports_disable_referential_integrity? then
          execute(tables.collect { |name| "ALTER TABLE #{quote_table_name(name)} ENABLE TRIGGER ALL" }.join(";"))
        end
      end

      # DATABASE STATEMENTS ======================================

      def explain(arel, binds = [])
        sql = "EXPLAIN #{to_sql(arel, binds)}"
        ExplainPrettyPrinter.new.pp(exec_query(sql, 'EXPLAIN', binds))
      end

      class ExplainPrettyPrinter # :nodoc:
        # Pretty prints the result of a EXPLAIN in a way that resembles the output of the
        # PostgreSQL shell:
        #
        #                                     QUERY PLAN
        #   ------------------------------------------------------------------------------
        #    Nested Loop Left Join  (cost=0.00..37.24 rows=8 width=0)
        #      Join Filter: (posts.user_id = users.id)
        #      ->  Index Scan using users_pkey on users  (cost=0.00..8.27 rows=1 width=4)
        #            Index Cond: (id = 1)
        #      ->  Seq Scan on posts  (cost=0.00..28.88 rows=8 width=4)
        #            Filter: (posts.user_id = 1)
        #   (6 rows)
        #
        def pp(result)
          header = result.columns.first
          lines  = result.rows.map(&:first)

          # We add 2 because there's one char of padding at both sides, note
          # the extra hyphens in the example above.
          width = [header, *lines].map(&:length).max + 2

          pp = []

          pp << header.center(width).rstrip
          pp << '-' * width

          pp += lines.map {|line| " #{line}"}

          nrows = result.rows.length
          rows_label = nrows == 1 ? 'row' : 'rows'
          pp << "(#{nrows} #{rows_label})"

          pp.join("\n") + "\n"
        end
      end

      # Executes a SELECT query and returns an array of rows. Each row is an
      # array of field values.
      def select_rows(sql, name = nil)
        select_raw(sql, name).last
      end

      # Executes an INSERT query and returns the new record's ID
      def insert_sql(sql, name = nil, pk = nil, id_value = nil, sequence_name = nil)
        unless pk
          # Extract the table from the insert sql. Yuck.
          table_ref = extract_table_ref_from_insert_sql(sql)
          pk = primary_key(table_ref) if table_ref
        end

        if pk
          select_value("#{sql} RETURNING #{quote_column_name(pk)}")
        else
          super
        end
      end
      alias :create :insert

      # create a 2D array representing the result set
      def result_as_array(res) #:nodoc:
        # check if we have any binary column and if they need escaping
        ftypes = Array.new(res.nfields) do |i|
          [i, res.ftype(i)]
        end

        rows = res.values
        return rows unless ftypes.any? { |_, x|
          x == BYTEA_COLUMN_TYPE_OID || x == MONEY_COLUMN_TYPE_OID
        }

        typehash = ftypes.group_by { |_, type| type }
        binaries = typehash[BYTEA_COLUMN_TYPE_OID] || []
        monies   = typehash[MONEY_COLUMN_TYPE_OID] || []

        rows.each do |row|
          # unescape string passed BYTEA field (OID == 17)
          binaries.each do |index, _|
            row[index] = unescape_bytea(row[index])
          end

          # If this is a money type column and there are any currency symbols,
          # then strip them off. Indeed it would be prettier to do this in
          # PostgreSQLColumn.string_to_decimal but would break form input
          # fields that call value_before_type_cast.
          monies.each do |index, _|
            data = row[index]
            # Because money output is formatted according to the locale, there are two
            # cases to consider (note the decimal separators):
            #  (1) $12,345,678.12
            #  (2) $12.345.678,12
            case data
            when /^-?\D+[\d,]+\.\d{2}$/  # (1)
              data.gsub!(/[^-\d.]/, '')
            when /^-?\D+[\d.]+,\d{2}$/  # (2)
              data.gsub!(/[^-\d,]/, '').sub!(/,/, '.')
            end
          end
        end
      end


      # Queries the database and returns the results in an Array-like object
      def query(sql, name = nil) #:nodoc:
        log(sql, name) do
          result_as_array @connection.async_exec(sql)
        end
      end

      # Executes an SQL statement, returning a PGresult object on success
      # or raising a PGError exception otherwise.
      def execute(sql, name = nil)
        log(sql, name) do
          @connection.async_exec(sql)
        end
      end

      def substitute_at(column, index)
        Arel::Nodes::BindParam.new "$#{index + 1}"
      end

      def exec_query(sql, name = 'SQL', binds = [])
        log(sql, name, binds) do
          result = binds.empty? ? exec_no_cache(sql, binds) :
                                  exec_cache(sql, binds)

          ret = ActiveRecord::Result.new(result.fields, result_as_array(result))
          result.clear
          return ret
        end
      end

      def exec_delete(sql, name = 'SQL', binds = [])
        log(sql, name, binds) do
          result = binds.empty? ? exec_no_cache(sql, binds) :
                                  exec_cache(sql, binds)
          affected = result.cmd_tuples
          result.clear
          affected
        end
      end
      alias :exec_update :exec_delete

      def sql_for_insert(sql, pk, id_value, sequence_name, binds)
        unless pk
          # Extract the table from the insert sql. Yuck.
          table_ref = extract_table_ref_from_insert_sql(sql)
          pk = primary_key(table_ref) if table_ref
        end

        sql = "#{sql} RETURNING #{quote_column_name(pk)}" if pk

        [sql, binds]
      end

      # Executes an UPDATE query and returns the number of affected tuples.
      def update_sql(sql, name = nil)
        super.cmd_tuples
      end

      # Begins a transaction.
      def begin_db_transaction
        execute "BEGIN"
      end

      # Commits a transaction.
      def commit_db_transaction
        execute "COMMIT"
      end

      # Aborts a transaction.
      def rollback_db_transaction
        execute "ROLLBACK"
      end

      def outside_transaction?
        @connection.transaction_status == PGconn::PQTRANS_IDLE
      end

      def create_savepoint
        execute("SAVEPOINT #{current_savepoint_name}")
      end

      def rollback_to_savepoint
        execute("ROLLBACK TO SAVEPOINT #{current_savepoint_name}")
      end

      def release_savepoint
        execute("RELEASE SAVEPOINT #{current_savepoint_name}")
      end

      # SCHEMA STATEMENTS ========================================

      # Drops the database specified on the +name+ attribute
      # and creates it again using the provided +options+.
      def recreate_database(name, options = {}) #:nodoc:
        drop_database(name)
        create_database(name, options)
      end

      # Create a new PostgreSQL database. Options include <tt>:owner</tt>, <tt>:template</tt>,
      # <tt>:encoding</tt>, <tt>:tablespace</tt>, and <tt>:connection_limit</tt> (note that MySQL uses
      # <tt>:charset</tt> while PostgreSQL uses <tt>:encoding</tt>).
      #
      # Example:
      #   create_database config[:database], config
      #   create_database 'foo_development', :encoding => 'unicode'
      def create_database(name, options = {})
        options = options.reverse_merge(:encoding => "utf8")

        option_string = options.symbolize_keys.sum do |key, value|
          case key
          when :owner
            " OWNER = \"#{value}\""
          when :template
            " TEMPLATE = \"#{value}\""
          when :encoding
            " ENCODING = '#{value}'"
          when :tablespace
            " TABLESPACE = \"#{value}\""
          when :connection_limit
            " CONNECTION LIMIT = #{value}"
          else
            ""
          end
        end

        execute "CREATE DATABASE #{quote_table_name(name)}#{option_string}"
      end

      # Drops a PostgreSQL database.
      #
      # Example:
      #   drop_database 'matt_development'
      def drop_database(name) #:nodoc:
        execute "DROP DATABASE IF EXISTS #{quote_table_name(name)}"
      end

      # Returns the list of all tables in the schema search path or a specified schema.
      def tables(name = nil)
        query(<<-SQL, 'SCHEMA').map { |row| row[0] }
          SELECT tablename
          FROM pg_tables
          WHERE schemaname = ANY (current_schemas(false))
        SQL
      end

      # Returns true if table exists.
      # If the schema is not specified as part of +name+ then it will only find tables within
      # the current schema search path (regardless of permissions to access tables in other schemas)
      def table_exists?(name)
        schema, table = Utils.extract_schema_and_table(name.to_s)
        return false unless table

        binds = [[nil, table]]
        binds << [nil, schema] if schema

        exec_query(<<-SQL, 'SCHEMA').rows.first[0].to_i > 0
            SELECT COUNT(*)
            FROM pg_class c
            LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relkind in ('v','r')
            AND c.relname = '#{table.gsub(/(^"|"$)/,'')}'
            AND n.nspname = #{schema ? "'#{schema}'" : 'ANY (current_schemas(false))'}
        SQL
      end

      # Returns true if schema exists.
      def schema_exists?(name)
        exec_query(<<-SQL, 'SCHEMA').rows.first[0].to_i > 0
          SELECT COUNT(*)
          FROM pg_namespace
          WHERE nspname = '#{name}'
        SQL
      end

      # Returns an array of indexes for the given table.
      def indexes(table_name, name = nil)
         result = query(<<-SQL, 'SCHEMA')
           SELECT distinct i.relname, d.indisunique, d.indkey, pg_get_indexdef(d.indexrelid), t.oid
           FROM pg_class t
           INNER JOIN pg_index d ON t.oid = d.indrelid
           INNER JOIN pg_class i ON d.indexrelid = i.oid
           WHERE i.relkind = 'i'
             AND d.indisprimary = 'f'
             AND t.relname = '#{table_name}'
             AND i.relnamespace IN (SELECT oid FROM pg_namespace WHERE nspname = ANY (current_schemas(false)) )
          ORDER BY i.relname
        SQL


        result.map do |row|
          index_name = row[0]
          unique = row[1] == 't'
          indkey = row[2].split(" ")
          inddef = row[3]
          oid = row[4]

          columns = Hash[query(<<-SQL, "SCHEMA")]
          SELECT a.attnum, a.attname
          FROM pg_attribute a
          WHERE a.attrelid = #{oid}
          AND a.attnum IN (#{indkey.join(",")})
          SQL

          column_names = columns.values_at(*indkey).compact

          # add info on sort order for columns (only desc order is explicitly specified, asc is the default)
          desc_order_columns = inddef.scan(/(\w+) DESC/).flatten
          orders = desc_order_columns.any? ? Hash[desc_order_columns.map {|order_column| [order_column, :desc]}] : {}

          column_names.empty? ? nil : IndexDefinition.new(table_name, index_name, unique, column_names, [], orders)
        end.compact
      end

      # Returns the list of all column definitions for a table.
      def columns(table_name, name = nil)
        # Limit, precision, and scale are all handled by the superclass.
        column_definitions(table_name).collect do |column_name, type, default, notnull|
          PostgreSQLColumn.new(column_name, default, type, notnull == 'f')
        end
      end

      # Returns the current database name.
      def current_database
        query('select current_database()', 'SCHEMA')[0][0]
      end

      # Returns the current schema name.
      def current_schema
        query('SELECT current_schema', 'SCHEMA')[0][0]
      end

      # Returns the current database encoding format.
      def encoding
        query(<<-end_sql, 'SCHEMA')[0][0]
          SELECT pg_encoding_to_char(pg_database.encoding) FROM pg_database
          WHERE pg_database.datname LIKE '#{current_database}'
        end_sql
      end

      # Sets the schema search path to a string of comma-separated schema names.
      # Names beginning with $ have to be quoted (e.g. $user => '$user').
      # See: http://www.postgresql.org/docs/current/static/ddl-schemas.html
      #
      # This should be not be called manually but set in database.yml.
      def schema_search_path=(schema_csv)
        if schema_csv
          execute("SET search_path TO #{schema_csv}", 'SCHEMA')
          @schema_search_path = schema_csv
        end
      end

      # Returns the active schema search path.
      def schema_search_path
        @schema_search_path ||= query('SHOW search_path', 'SCHEMA')[0][0]
      end

      # Returns the current client message level.
      def client_min_messages
        query('SHOW client_min_messages', 'SCHEMA')[0][0]
      end

      # Set the client message level.
      def client_min_messages=(level)
        execute("SET client_min_messages TO '#{level}'", 'SCHEMA')
      end

      # Returns the sequence name for a table's primary key or some other specified key.
      def default_sequence_name(table_name, pk = nil) #:nodoc:
        serial_sequence(table_name, pk || 'id').split('.').last
      rescue ActiveRecord::StatementInvalid
        "#{table_name}_#{pk || 'id'}_seq"
      end

      def serial_sequence(table, column)
        result = exec_query(<<-eosql, 'SCHEMA')
          SELECT pg_get_serial_sequence('#{table}', '#{column}')
        eosql
        result.rows.first.first
      end

      # Resets the sequence of a table's primary key to the maximum value.
      def reset_pk_sequence!(table, pk = nil, sequence = nil) #:nodoc:
        unless pk and sequence
          default_pk, default_sequence = pk_and_sequence_for(table)

          pk ||= default_pk
          sequence ||= default_sequence
        end

        if @logger && pk && !sequence
          @logger.warn "#{table} has primary key #{pk} with no default sequence"
        end

        if pk && sequence
          quoted_sequence = quote_table_name(sequence)

          select_value <<-end_sql, 'SCHEMA'
            SELECT setval('#{quoted_sequence}', (SELECT COALESCE(MAX(#{quote_column_name pk})+(SELECT increment_by FROM #{quoted_sequence}), (SELECT min_value FROM #{quoted_sequence})) FROM #{quote_table_name(table)}), false)
          end_sql
        end
      end

      # Returns a table's primary key and belonging sequence.
      def pk_and_sequence_for(table) #:nodoc:
        # First try looking for a sequence with a dependency on the
        # given table's primary key.
        result = query(<<-end_sql, 'SCHEMA')[0]
          SELECT attr.attname, seq.relname
          FROM pg_class      seq,
               pg_attribute  attr,
               pg_depend     dep,
               pg_namespace  name,
               pg_constraint cons
          WHERE seq.oid           = dep.objid
            AND seq.relkind       = 'S'
            AND attr.attrelid     = dep.refobjid
            AND attr.attnum       = dep.refobjsubid
            AND attr.attrelid     = cons.conrelid
            AND attr.attnum       = cons.conkey[1]
            AND cons.contype      = 'p'
            AND dep.refobjid      = '#{quote_table_name(table)}'::regclass
        end_sql

        if result.nil? or result.empty?
          result = query(<<-end_sql, 'SCHEMA')[0]
            SELECT attr.attname,
              CASE
                WHEN split_part(pg_get_expr(def.adbin, def.adrelid), '''', 2) ~ '.' THEN
                  substr(split_part(pg_get_expr(def.adbin, def.adrelid), '''', 2),
                         strpos(split_part(pg_get_expr(def.adbin, def.adrelid), '''', 2), '.')+1)
                ELSE split_part(pg_get_expr(def.adbin, def.adrelid), '''', 2)
              END
            FROM pg_class       t
            JOIN pg_attribute   attr ON (t.oid = attrelid)
            JOIN pg_attrdef     def  ON (adrelid = attrelid AND adnum = attnum)
            JOIN pg_constraint  cons ON (conrelid = adrelid AND adnum = conkey[1])
            WHERE t.oid = '#{quote_table_name(table)}'::regclass
              AND cons.contype = 'p'
              AND pg_get_expr(def.adbin, def.adrelid) ~* 'nextval'
          end_sql
        end

        [result.first, result.last]
      rescue
        nil
      end

      # Returns just a table's primary key
      def primary_key(table)
        row = exec_query(<<-end_sql, 'SCHEMA').rows.first
          SELECT DISTINCT(attr.attname)
          FROM pg_attribute attr
          INNER JOIN pg_depend dep ON attr.attrelid = dep.refobjid AND attr.attnum = dep.refobjsubid
          INNER JOIN pg_constraint cons ON attr.attrelid = cons.conrelid AND attr.attnum = cons.conkey[1]
          WHERE cons.contype = 'p'
            AND dep.refobjid = '#{quote_table_name(table)}'::regclass
        end_sql

        row && row.first
      end

      # Renames a table.
      # Also renames a table's primary key sequence if the sequence name matches the
      # Active Record default.
      #
      # Example:
      #   rename_table('octopuses', 'octopi')
      def rename_table(name, new_name)
        clear_cache!
        execute "ALTER TABLE #{quote_table_name(name)} RENAME TO #{quote_table_name(new_name)}"
        pk, seq = pk_and_sequence_for(new_name)
        if seq == "#{name}_#{pk}_seq"
          new_seq = "#{new_name}_#{pk}_seq"
          execute "ALTER TABLE #{quote_table_name(seq)} RENAME TO #{quote_table_name(new_seq)}"
        end
      end

      # Adds a new column to the named table.
      # See TableDefinition#column for details of the options you can use.
      def add_column(table_name, column_name, type, options = {})
        clear_cache!
        add_column_sql = "ALTER TABLE #{quote_table_name(table_name)} ADD COLUMN #{quote_column_name(column_name)} #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"
        add_column_options!(add_column_sql, options)

        execute add_column_sql
      end

      # Changes the column of a table.
      def change_column(table_name, column_name, type, options = {})
        clear_cache!
        quoted_table_name = quote_table_name(table_name)

        execute "ALTER TABLE #{quoted_table_name} ALTER COLUMN #{quote_column_name(column_name)} TYPE #{type_to_sql(type, options[:limit], options[:precision], options[:scale])}"

        change_column_default(table_name, column_name, options[:default]) if options_include_default?(options)
        change_column_null(table_name, column_name, options[:null], options[:default]) if options.key?(:null)
      end

      # Changes the default value of a table column.
      def change_column_default(table_name, column_name, default)
        clear_cache!
        execute "ALTER TABLE #{quote_table_name(table_name)} ALTER COLUMN #{quote_column_name(column_name)} SET DEFAULT #{quote(default)}"
      end

      def change_column_null(table_name, column_name, null, default = nil)
        clear_cache!
        unless null || default.nil?
          execute("UPDATE #{quote_table_name(table_name)} SET #{quote_column_name(column_name)}=#{quote(default)} WHERE #{quote_column_name(column_name)} IS NULL")
        end
        execute("ALTER TABLE #{quote_table_name(table_name)} ALTER #{quote_column_name(column_name)} #{null ? 'DROP' : 'SET'} NOT NULL")
      end

      # Renames a column in a table.
      def rename_column(table_name, column_name, new_column_name)
        clear_cache!
        execute "ALTER TABLE #{quote_table_name(table_name)} RENAME COLUMN #{quote_column_name(column_name)} TO #{quote_column_name(new_column_name)}"
      end

      def remove_index!(table_name, index_name) #:nodoc:
        execute "DROP INDEX #{quote_table_name(index_name)}"
      end

      def rename_index(table_name, old_name, new_name)
        execute "ALTER INDEX #{quote_column_name(old_name)} RENAME TO #{quote_table_name(new_name)}"
      end

      def index_name_length
        63
      end

      # Maps logical Rails types to PostgreSQL-specific data types.
      def type_to_sql(type, limit = nil, precision = nil, scale = nil)
        case type.to_s
        when 'binary'
          # PostgreSQL doesn't support limits on binary (bytea) columns.
          # The hard limit is 1Gb, because of a 32-bit size field, and TOAST.
          case limit
          when nil, 0..0x3fffffff; super(type)
          else raise(ActiveRecordError, "No binary type has byte size #{limit}.")
          end
        when 'integer'
          return 'integer' unless limit

          case limit
            when 1, 2; 'smallint'
            when 3, 4; 'integer'
            when 5..8; 'bigint'
            else raise(ActiveRecordError, "No integer type has byte size #{limit}. Use a numeric with precision 0 instead.")
          end
        else
          super
        end
      end

      # Returns a SELECT DISTINCT clause for a given set of columns and a given ORDER BY clause.
      #
      # PostgreSQL requires the ORDER BY columns in the select list for distinct queries, and
      # requires that the ORDER BY include the distinct column.
      #
      #   distinct("posts.id", "posts.created_at desc")
      def distinct(columns, orders) #:nodoc:
        return "DISTINCT #{columns}" if orders.empty?

        # Construct a clean list of column names from the ORDER BY clause, removing
        # any ASC/DESC modifiers
        order_columns = orders.collect { |s| s.gsub(/\s+(ASC|DESC)\s*(NULLS\s+(FIRST|LAST)\s*)?/i, '') }
        order_columns.delete_if { |c| c.blank? }
        order_columns = order_columns.zip((0...order_columns.size).to_a).map { |s,i| "#{s} AS alias_#{i}" }

        "DISTINCT #{columns}, #{order_columns * ', '}"
      end

      module Utils
        extend self

        # Returns an array of <tt>[schema_name, table_name]</tt> extracted from +name+.
        # +schema_name+ is nil if not specified in +name+.
        # +schema_name+ and +table_name+ exclude surrounding quotes (regardless of whether provided in +name+)
        # +name+ supports the range of schema/table references understood by PostgreSQL, for example:
        #
        # * <tt>table_name</tt>
        # * <tt>"table.name"</tt>
        # * <tt>schema_name.table_name</tt>
        # * <tt>schema_name."table.name"</tt>
        # * <tt>"schema.name"."table name"</tt>
        def extract_schema_and_table(name)
          table, schema = name.scan(/[^".\s]+|"[^"]*"/)[0..1].collect{|m| m.gsub(/(^"|"$)/,'') }.reverse
          [schema, table]
        end
      end

      protected
        # Returns the version of the connected PostgreSQL server.
        def postgresql_version
          @connection.server_version
        end

        def translate_exception(exception, message)
          case exception.message
          when /duplicate key value violates unique constraint/
            RecordNotUnique.new(message, exception)
          when /violates foreign key constraint/
            InvalidForeignKey.new(message, exception)
          else
            super
          end
        end

      private
        FEATURE_NOT_SUPPORTED = "0A000" # :nodoc:

        def exec_no_cache(sql, binds)
          @connection.async_exec(sql)
        end

        def exec_cache(sql, binds)
          begin
            stmt_key = prepare_statement sql

            # Clear the queue
            @connection.get_last_result
            @connection.send_query_prepared(stmt_key, binds.map { |col, val|
              type_cast(val, col)
            })
            @connection.block
            @connection.get_last_result
          rescue PGError => e
            # Get the PG code for the failure.  Annoyingly, the code for
            # prepared statements whose return value may have changed is
            # FEATURE_NOT_SUPPORTED.  Check here for more details:
            # http://git.postgresql.org/gitweb/?p=postgresql.git;a=blob;f=src/backend/utils/cache/plancache.c#l573
            code = e.result.result_error_field(PGresult::PG_DIAG_SQLSTATE)
            if FEATURE_NOT_SUPPORTED == code
              @statements.delete sql_key(sql)
              retry
            else
              raise e
            end
          end
        end

        # Returns the statement identifier for the client side cache
        # of statements
        def sql_key(sql)
          "#{schema_search_path}-#{sql}"
        end

        # Prepare the statement if it hasn't been prepared, return
        # the statement key.
        def prepare_statement(sql)
          sql_key = sql_key(sql)
          unless @statements.key? sql_key
            nextkey = @statements.next_key
            @connection.prepare nextkey, sql
            @statements[sql_key] = nextkey
          end
          @statements[sql_key]
        end

        # The internal PostgreSQL identifier of the money data type.
        MONEY_COLUMN_TYPE_OID = 790 #:nodoc:
        # The internal PostgreSQL identifier of the BYTEA data type.
        BYTEA_COLUMN_TYPE_OID = 17 #:nodoc:

        # Connects to a PostgreSQL server and sets up the adapter depending on the
        # connected server's characteristics.
        def connect
          @connection = PGconn.connect(*@connection_parameters)

          # Money type has a fixed precision of 10 in PostgreSQL 8.2 and below, and as of
          # PostgreSQL 8.3 it has a fixed precision of 19. PostgreSQLColumn.extract_precision
          # should know about this but can't detect it there, so deal with it here.
          PostgreSQLColumn.money_precision = (postgresql_version >= 80300) ? 19 : 10

          configure_connection
        end

        # Configures the encoding, verbosity, schema search path, and time zone of the connection.
        # This is called by #connect and should not be called manually.
        def configure_connection
          if @config[:encoding]
            @connection.set_client_encoding(@config[:encoding])
          end
          self.client_min_messages = @config[:min_messages] if @config[:min_messages]
          self.schema_search_path = @config[:schema_search_path] || @config[:schema_order]

          # Use standard-conforming strings if available so we don't have to do the E'...' dance.
          set_standard_conforming_strings

          # If using Active Record's time zone support configure the connection to return
          # TIMESTAMP WITH ZONE types in UTC.
          if ActiveRecord::Base.default_timezone == :utc
            execute("SET time zone 'UTC'", 'SCHEMA')
          elsif @local_tz
            execute("SET time zone '#{@local_tz}'", 'SCHEMA')
          end
        end

        # Returns the current ID of a table's sequence.
        def last_insert_id(sequence_name) #:nodoc:
          r = exec_query("SELECT currval('#{sequence_name}')", 'SQL')
          Integer(r.rows.first.first)
        end

        # Executes a SELECT query and returns the results, performing any data type
        # conversions that are required to be performed here instead of in PostgreSQLColumn.
        def select(sql, name = nil, binds = [])
          exec_query(sql, name, binds).to_a
        end

        def select_raw(sql, name = nil)
          res = execute(sql, name)
          results = result_as_array(res)
          fields = res.fields
          res.clear
          return fields, results
        end

        # Returns the list of a table's column names, data types, and default values.
        #
        # The underlying query is roughly:
        #  SELECT column.name, column.type, default.value
        #    FROM column LEFT JOIN default
        #      ON column.table_id = default.table_id
        #     AND column.num = default.column_num
        #   WHERE column.table_id = get_table_id('table_name')
        #     AND column.num > 0
        #     AND NOT column.is_dropped
        #   ORDER BY column.num
        #
        # If the table name is not prefixed with a schema, the database will
        # take the first match from the schema search path.
        #
        # Query implementation notes:
        #  - format_type includes the column size constraint, e.g. varchar(50)
        #  - ::regclass is a function that gives the id for a table name
        def column_definitions(table_name) #:nodoc:
          exec_query(<<-end_sql, 'SCHEMA').rows
            SELECT a.attname, format_type(a.atttypid, a.atttypmod),
                     pg_get_expr(d.adbin, d.adrelid), a.attnotnull, a.atttypid, a.atttypmod
              FROM pg_attribute a LEFT JOIN pg_attrdef d
                ON a.attrelid = d.adrelid AND a.attnum = d.adnum
             WHERE a.attrelid = '#{quote_table_name(table_name)}'::regclass
               AND a.attnum > 0 AND NOT a.attisdropped
             ORDER BY a.attnum
          end_sql
        end

        def extract_pg_identifier_from_name(name)
          match_data = name.start_with?('"') ? name.match(/\"([^\"]+)\"/) : name.match(/([^\.]+)/)

          if match_data
            rest = name[match_data[0].length, name.length]
            rest = rest[1, rest.length] if rest.start_with? "."
            [match_data[1], (rest.length > 0 ? rest : nil)]
          end
        end

        def extract_table_ref_from_insert_sql(sql)
          sql[/into\s+([^\(]*).*values\s*\(/i]
          $1.strip if $1
        end

        def table_definition
          TableDefinition.new(self)
        end
    end
  end
end
module ActiveRecord
  module ConnectionAdapters
    class SchemaCache
      attr_reader :columns, :columns_hash, :primary_keys, :tables
      attr_reader :connection

      def initialize(conn)
        @connection = conn
        @tables     = {}

        @columns = Hash.new do |h, table_name|
          h[table_name] = conn.columns(table_name, "#{table_name} Columns")
        end

        @columns_hash = Hash.new do |h, table_name|
          h[table_name] = Hash[columns[table_name].map { |col|
            [col.name, col]
          }]
        end

        @primary_keys = Hash.new do |h, table_name|
          h[table_name] = table_exists?(table_name) ? conn.primary_key(table_name) : nil
        end
      end

      # A cached lookup for table existence.
      def table_exists?(name)
        return @tables[name] if @tables.key? name

        @tables[name] = connection.table_exists?(name)
      end

      # Clears out internal caches
      def clear!
        @columns.clear
        @columns_hash.clear
        @primary_keys.clear
        @tables.clear
      end

      # Clear out internal caches for table with +table_name+.
      def clear_table_cache!(table_name)
        @columns.delete table_name
        @columns_hash.delete table_name
        @primary_keys.delete table_name
        @tables.delete table_name
      end
    end
  end
end
require 'active_record/connection_adapters/sqlite_adapter'

gem 'sqlite3', '~> 1.3.5'
require 'sqlite3'

module ActiveRecord
  class Base
    # sqlite3 adapter reuses sqlite_connection.
    def self.sqlite3_connection(config) # :nodoc:
      # Require database.
      unless config[:database]
        raise ArgumentError, "No database file specified. Missing argument: database"
      end

      # Allow database path relative to Rails.root, but only if
      # the database path is not the special path that tells
      # Sqlite to build a database only in memory.
      if defined?(Rails.root) && ':memory:' != config[:database]
        config[:database] = File.expand_path(config[:database], Rails.root)
      end

      unless 'sqlite3' == config[:adapter]
        raise ArgumentError, 'adapter name should be "sqlite3"'
      end

      db = SQLite3::Database.new(
        config[:database],
        :results_as_hash => true
      )

      db.busy_timeout(config[:timeout]) if config[:timeout]

      ConnectionAdapters::SQLite3Adapter.new(db, logger, config)
    end
  end

  module ConnectionAdapters #:nodoc:
    class SQLite3Adapter < SQLiteAdapter # :nodoc:
      def quote(value, column = nil)
        if value.kind_of?(String) && column && column.type == :binary && column.class.respond_to?(:string_to_binary)
          s = column.class.string_to_binary(value).unpack("H*")[0]
          "x'#{s}'"
        else
          super
        end
      end

      # Returns the current database encoding format as a string, eg: 'UTF-8'
      def encoding
        @connection.encoding.to_s
      end

    end
  end
end
require 'active_record/connection_adapters/abstract_adapter'
require 'active_record/connection_adapters/statement_pool'
require 'active_support/core_ext/string/encoding'
require 'arel/visitors/bind_visitor'

module ActiveRecord
  module ConnectionAdapters #:nodoc:
    class SQLiteColumn < Column #:nodoc:
      class <<  self
        def binary_to_string(value)
          if value.respond_to?(:force_encoding) && value.encoding != Encoding::ASCII_8BIT
            value = value.force_encoding(Encoding::ASCII_8BIT)
          end
          value
        end
      end
    end

    # The SQLite adapter works with both the 2.x and 3.x series of SQLite with the sqlite-ruby
    # drivers (available both as gems and from http://rubyforge.org/projects/sqlite-ruby/).
    #
    # Options:
    #
    # * <tt>:database</tt> - Path to the database file.
    class SQLiteAdapter < AbstractAdapter
      class Version
        include Comparable

        def initialize(version_string)
          @version = version_string.split('.').map { |v| v.to_i }
        end

        def <=>(version_string)
          @version <=> version_string.split('.').map { |v| v.to_i }
        end
      end

      class StatementPool < ConnectionAdapters::StatementPool
        def initialize(connection, max)
          super
          @cache = Hash.new { |h,pid| h[pid] = {} }
        end

        def each(&block); cache.each(&block); end
        def key?(key);    cache.key?(key); end
        def [](key);      cache[key]; end
        def length;       cache.length; end

        def []=(sql, key)
          while @max <= cache.size
            dealloc(cache.shift.last[:stmt])
          end
          cache[sql] = key
        end

        def clear
          cache.values.each do |hash|
            dealloc hash[:stmt]
          end
          cache.clear
        end

        private
        def cache
          @cache[$$]
        end

        def dealloc(stmt)
          stmt.close unless stmt.closed?
        end
      end

      class BindSubstitution < Arel::Visitors::SQLite # :nodoc:
        include Arel::Visitors::BindVisitor
      end

      def initialize(connection, logger, config)
        super(connection, logger)
        @statements = StatementPool.new(@connection,
                                        config.fetch(:statement_limit) { 1000 })
        @config = config

        if config.fetch(:prepared_statements) { true }
          @visitor = Arel::Visitors::SQLite.new self
        else
          @visitor = BindSubstitution.new self
        end
      end

      def adapter_name #:nodoc:
        'SQLite'
      end

      # Returns true if SQLite version is '2.0.0' or greater, false otherwise.
      def supports_ddl_transactions?
        sqlite_version >= '2.0.0'
      end

      # Returns true if SQLite version is '3.6.8' or greater, false otherwise.
      def supports_savepoints?
        sqlite_version >= '3.6.8'
      end

      # Returns true, since this connection adapter supports prepared statement
      # caching.
      def supports_statement_cache?
        true
      end

      # Returns true, since this connection adapter supports migrations.
      def supports_migrations? #:nodoc:
        true
      end

      # Returns true.
      def supports_primary_key? #:nodoc:
        true
      end

      # Returns true.
      def supports_explain?
        true
      end

      def requires_reloading?
        true
      end

      # Returns true if SQLite version is '3.1.6' or greater, false otherwise.
      def supports_add_column?
        sqlite_version >= '3.1.6'
      end

      # Disconnects from the database if already connected. Otherwise, this
      # method does nothing.
      def disconnect!
        super
        clear_cache!
        @connection.close rescue nil
      end

      # Clears the prepared statements cache.
      def clear_cache!
        @statements.clear
      end

      # Returns true if SQLite version is '3.2.6' or greater, false otherwise.
      def supports_count_distinct? #:nodoc:
        sqlite_version >= '3.2.6'
      end

      # Returns true if SQLite version is '3.1.0' or greater, false otherwise.
      def supports_autoincrement? #:nodoc:
        sqlite_version >= '3.1.0'
      end

      def supports_index_sort_order?
        sqlite_version >= '3.3.0'
      end

      def native_database_types #:nodoc:
        {
          :primary_key => default_primary_key_type,
          :string      => { :name => "varchar", :limit => 255 },
          :text        => { :name => "text" },
          :integer     => { :name => "integer" },
          :float       => { :name => "float" },
          :decimal     => { :name => "decimal" },
          :datetime    => { :name => "datetime" },
          :timestamp   => { :name => "datetime" },
          :time        => { :name => "time" },
          :date        => { :name => "date" },
          :binary      => { :name => "blob" },
          :boolean     => { :name => "boolean" }
        }
      end


      # QUOTING ==================================================

      def quote_string(s) #:nodoc:
        @connection.class.quote(s)
      end

      def quote_column_name(name) #:nodoc:
        %Q("#{name.to_s.gsub('"', '""')}")
      end

      # Quote date/time values for use in SQL input. Includes microseconds
      # if the value is a Time responding to usec.
      def quoted_date(value) #:nodoc:
        if value.respond_to?(:usec)
          "#{super}.#{sprintf("%06d", value.usec)}"
        else
          super
        end
      end

      if "<3".encoding_aware?
        def type_cast(value, column) # :nodoc:
          return value.to_f if BigDecimal === value
          return super unless String === value
          return super unless column && value

          value = super
          if column.type == :string && value.encoding == Encoding::ASCII_8BIT
            logger.error "Binary data inserted for `string` type on column `#{column.name}`" if logger
            value = value.encode Encoding::UTF_8
          end
          value
        end
      else
        def type_cast(value, column) # :nodoc:
          return super unless BigDecimal === value

          value.to_f
        end
      end

      # DATABASE STATEMENTS ======================================

      def explain(arel, binds = [])
        sql = "EXPLAIN QUERY PLAN #{to_sql(arel, binds)}"
        ExplainPrettyPrinter.new.pp(exec_query(sql, 'EXPLAIN', binds))
      end

      class ExplainPrettyPrinter
        # Pretty prints the result of a EXPLAIN QUERY PLAN in a way that resembles
        # the output of the SQLite shell:
        #
        #   0|0|0|SEARCH TABLE users USING INTEGER PRIMARY KEY (rowid=?) (~1 rows)
        #   0|1|1|SCAN TABLE posts (~100000 rows)
        #
        def pp(result) # :nodoc:
          result.rows.map do |row|
            row.join('|')
          end.join("\n") + "\n"
        end
      end

      def exec_query(sql, name = nil, binds = [])
        log(sql, name, binds) do

          # Don't cache statements without bind values
          if binds.empty?
            stmt    = @connection.prepare(sql)
            cols    = stmt.columns
            records = stmt.to_a
            stmt.close
            stmt = records
          else
            cache = @statements[sql] ||= {
              :stmt => @connection.prepare(sql)
            }
            stmt = cache[:stmt]
            cols = cache[:cols] ||= stmt.columns
            stmt.reset!
            stmt.bind_params binds.map { |col, val|
              type_cast(val, col)
            }
          end

          ActiveRecord::Result.new(cols, stmt.to_a)
        end
      end

      def exec_delete(sql, name = 'SQL', binds = [])
        exec_query(sql, name, binds)
        @connection.changes
      end
      alias :exec_update :exec_delete

      def last_inserted_id(result)
        @connection.last_insert_row_id
      end

      def execute(sql, name = nil) #:nodoc:
        log(sql, name) { @connection.execute(sql) }
      end

      def update_sql(sql, name = nil) #:nodoc:
        super
        @connection.changes
      end

      def delete_sql(sql, name = nil) #:nodoc:
        sql += " WHERE 1=1" unless sql =~ /WHERE/i
        super sql, name
      end

      def insert_sql(sql, name = nil, pk = nil, id_value = nil, sequence_name = nil) #:nodoc:
        super
        id_value || @connection.last_insert_row_id
      end
      alias :create :insert_sql

      def select_rows(sql, name = nil)
        exec_query(sql, name).rows
      end

      def create_savepoint
        execute("SAVEPOINT #{current_savepoint_name}")
      end

      def rollback_to_savepoint
        execute("ROLLBACK TO SAVEPOINT #{current_savepoint_name}")
      end

      def release_savepoint
        execute("RELEASE SAVEPOINT #{current_savepoint_name}")
      end

      def begin_db_transaction #:nodoc:
        log('begin transaction',nil) { @connection.transaction }
      end

      def commit_db_transaction #:nodoc:
        log('commit transaction',nil) { @connection.commit }
      end

      def rollback_db_transaction #:nodoc:
        log('rollback transaction',nil) { @connection.rollback }
      end

      # SCHEMA STATEMENTS ========================================

      def tables(name = 'SCHEMA', table_name = nil) #:nodoc:
        sql = <<-SQL
          SELECT name
          FROM sqlite_master
          WHERE type = 'table' AND NOT name = 'sqlite_sequence'
        SQL
        sql << " AND name = #{quote_table_name(table_name)}" if table_name

        exec_query(sql, name).map do |row|
          row['name']
        end
      end

      def table_exists?(name)
        name && tables('SCHEMA', name).any?
      end

      # Returns an array of +SQLiteColumn+ objects for the table specified by +table_name+.
      def columns(table_name, name = nil) #:nodoc:
        table_structure(table_name).map do |field|
          case field["dflt_value"]
          when /^null$/i
            field["dflt_value"] = nil
          when /^'(.*)'$/
            field["dflt_value"] = $1.gsub(/''/, "'")
          when /^"(.*)"$/
            field["dflt_value"] = $1.gsub(/""/, '"')
          end

          SQLiteColumn.new(field['name'], field['dflt_value'], field['type'], field['notnull'].to_i == 0)
        end
      end

      # Returns an array of indexes for the given table.
      def indexes(table_name, name = nil) #:nodoc:
        exec_query("PRAGMA index_list(#{quote_table_name(table_name)})", 'SCHEMA').map do |row|
          IndexDefinition.new(
            table_name,
            row['name'],
            row['unique'] != 0,
            exec_query("PRAGMA index_info('#{row['name']}')", 'SCHEMA').map { |col|
              col['name']
            })
        end
      end

      def primary_key(table_name) #:nodoc:
        column = table_structure(table_name).find { |field|
          field['pk'] == 1
        }
        column && column['name']
      end

      def remove_index!(table_name, index_name) #:nodoc:
        exec_query "DROP INDEX #{quote_column_name(index_name)}"
      end

      # Renames a table.
      #
      # Example:
      #   rename_table('octopuses', 'octopi')
      def rename_table(name, new_name)
        exec_query "ALTER TABLE #{quote_table_name(name)} RENAME TO #{quote_table_name(new_name)}"
      end

      # See: http://www.sqlite.org/lang_altertable.html
      # SQLite has an additional restriction on the ALTER TABLE statement
      def valid_alter_table_options( type, options)
        type.to_sym != :primary_key
      end

      def add_column(table_name, column_name, type, options = {}) #:nodoc:
        if supports_add_column? && valid_alter_table_options( type, options )
          super(table_name, column_name, type, options)
        else
          alter_table(table_name) do |definition|
            definition.column(column_name, type, options)
          end
        end
      end

      def remove_column(table_name, *column_names) #:nodoc:
        raise ArgumentError.new("You must specify at least one column name. Example: remove_column(:people, :first_name)") if column_names.empty?

        if column_names.flatten!
          message = 'Passing array to remove_columns is deprecated, please use ' +
                    'multiple arguments, like: `remove_columns(:posts, :foo, :bar)`'
          ActiveSupport::Deprecation.warn message, caller
        end

        column_names.each do |column_name|
          alter_table(table_name) do |definition|
            definition.columns.delete(definition[column_name])
          end
        end
      end
      alias :remove_columns :remove_column

      def change_column_default(table_name, column_name, default) #:nodoc:
        alter_table(table_name) do |definition|
          definition[column_name].default = default
        end
      end

      def change_column_null(table_name, column_name, null, default = nil)
        unless null || default.nil?
          exec_query("UPDATE #{quote_table_name(table_name)} SET #{quote_column_name(column_name)}=#{quote(default)} WHERE #{quote_column_name(column_name)} IS NULL")
        end
        alter_table(table_name) do |definition|
          definition[column_name].null = null
        end
      end

      def change_column(table_name, column_name, type, options = {}) #:nodoc:
        alter_table(table_name) do |definition|
          include_default = options_include_default?(options)
          definition[column_name].instance_eval do
            self.type    = type
            self.limit   = options[:limit] if options.include?(:limit)
            self.default = options[:default] if include_default
            self.null    = options[:null] if options.include?(:null)
            self.precision = options[:precision] if options.include?(:precision)
            self.scale   = options[:scale] if options.include?(:scale)
          end
        end
      end

      def rename_column(table_name, column_name, new_column_name) #:nodoc:
        unless columns(table_name).detect{|c| c.name == column_name.to_s }
          raise ActiveRecord::ActiveRecordError, "Missing column #{table_name}.#{column_name}"
        end
        alter_table(table_name, :rename => {column_name.to_s => new_column_name.to_s})
      end

      def empty_insert_statement_value
        "VALUES(NULL)"
      end

      protected
        def select(sql, name = nil, binds = []) #:nodoc:
          exec_query(sql, name, binds).to_a
        end

        def table_structure(table_name)
          structure = exec_query("PRAGMA table_info(#{quote_table_name(table_name)})", 'SCHEMA').to_hash
          raise(ActiveRecord::StatementInvalid, "Could not find table '#{table_name}'") if structure.empty?
          structure
        end

        def alter_table(table_name, options = {}) #:nodoc:
          altered_table_name = "altered_#{table_name}"
          caller = lambda {|definition| yield definition if block_given?}

          transaction do
            move_table(table_name, altered_table_name,
              options.merge(:temporary => true))
            move_table(altered_table_name, table_name, &caller)
          end
        end

        def move_table(from, to, options = {}, &block) #:nodoc:
          copy_table(from, to, options, &block)
          drop_table(from)
        end

        def copy_table(from, to, options = {}) #:nodoc:
          options = options.merge(:id => (!columns(from).detect{|c| c.name == 'id'}.nil? && 'id' == primary_key(from).to_s))
          create_table(to, options) do |definition|
            @definition = definition
            columns(from).each do |column|
              column_name = options[:rename] ?
                (options[:rename][column.name] ||
                 options[:rename][column.name.to_sym] ||
                 column.name) : column.name

              @definition.column(column_name, column.type,
                :limit => column.limit, :default => column.default,
                :precision => column.precision, :scale => column.scale,
                :null => column.null)
            end
            @definition.primary_key(primary_key(from)) if primary_key(from)
            yield @definition if block_given?
          end

          copy_table_indexes(from, to, options[:rename] || {})
          copy_table_contents(from, to,
            @definition.columns.map {|column| column.name},
            options[:rename] || {})
        end

        def copy_table_indexes(from, to, rename = {}) #:nodoc:
          indexes(from).each do |index|
            name = index.name
            if to == "altered_#{from}"
              name = "temp_#{name}"
            elsif from == "altered_#{to}"
              name = name[5..-1]
            end

            to_column_names = columns(to).map { |c| c.name }
            columns = index.columns.map {|c| rename[c] || c }.select do |column|
              to_column_names.include?(column)
            end

            unless columns.empty?
              # index name can't be the same
              opts = { :name => name.gsub(/_(#{from})_/, "_#{to}_") }
              opts[:unique] = true if index.unique
              add_index(to, columns, opts)
            end
          end
        end

        def copy_table_contents(from, to, columns, rename = {}) #:nodoc:
          column_mappings = Hash[columns.map {|name| [name, name]}]
          rename.each { |a| column_mappings[a.last] = a.first }
          from_columns = columns(from).collect {|col| col.name}
          columns = columns.find_all{|col| from_columns.include?(column_mappings[col])}
          quoted_columns = columns.map { |col| quote_column_name(col) } * ','

          quoted_to = quote_table_name(to)
          exec_query("SELECT * FROM #{quote_table_name(from)}").each do |row|
            sql = "INSERT INTO #{quoted_to} (#{quoted_columns}) VALUES ("
            sql << columns.map {|col| quote row[column_mappings[col]]} * ', '
            sql << ')'
            exec_query sql
          end
        end

        def sqlite_version
          @sqlite_version ||= SQLiteAdapter::Version.new(select_value('select sqlite_version(*)'))
        end

        def default_primary_key_type
          if supports_autoincrement?
            'INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL'
          else
            'INTEGER PRIMARY KEY NOT NULL'
          end
        end

        def translate_exception(exception, message)
          case exception.message
          when /column(s)? .* (is|are) not unique/
            RecordNotUnique.new(message, exception)
          else
            super
          end
        end

    end
  end
end
module ActiveRecord
  module ConnectionAdapters
    class StatementPool
      include Enumerable

      def initialize(connection, max = 1000)
        @connection = connection
        @max        = max
      end

      def each
        raise NotImplementedError
      end

      def key?(key)
        raise NotImplementedError
      end

      def [](key)
        raise NotImplementedError
      end

      def length
        raise NotImplementedError
      end

      def []=(sql, key)
        raise NotImplementedError
      end

      def clear
        raise NotImplementedError
      end

      def delete(key)
        raise NotImplementedError
      end
    end
  end
end
module ActiveRecord
  # = Active Record Counter Cache
  module CounterCache
    # Resets one or more counter caches to their correct value using an SQL
    # count query. This is useful when adding new counter caches, or if the
    # counter has been corrupted or modified directly by SQL.
    #
    # ==== Parameters
    #
    # * +id+ - The id of the object you wish to reset a counter on.
    # * +counters+ - One or more counter names to reset
    #
    # ==== Examples
    #
    #   # For Post with id #1 records reset the comments_count
    #   Post.reset_counters(1, :comments)
    def reset_counters(id, *counters)
      object = find(id)
      counters.each do |association|
        has_many_association = reflect_on_association(association.to_sym)

        if has_many_association.options[:as]
          has_many_association.options[:as].to_s.classify
        else
          self.name
        end

        if has_many_association.is_a? ActiveRecord::Reflection::ThroughReflection
          has_many_association = has_many_association.through_reflection
        end

        foreign_key  = has_many_association.foreign_key.to_s
        child_class  = has_many_association.klass
        belongs_to   = child_class.reflect_on_all_associations(:belongs_to)
        reflection   = belongs_to.find { |e| e.foreign_key.to_s == foreign_key && e.options[:counter_cache].present? }
        counter_name = reflection.counter_cache_column

        stmt = unscoped.where(arel_table[primary_key].eq(object.id)).arel.compile_update({
          arel_table[counter_name] => object.send(association).count
        })
        connection.update stmt
      end
      return true
    end

    # A generic "counter updater" implementation, intended primarily to be
    # used by increment_counter and decrement_counter, but which may also
    # be useful on its own. It simply does a direct SQL update for the record
    # with the given ID, altering the given hash of counters by the amount
    # given by the corresponding value:
    #
    # ==== Parameters
    #
    # * +id+ - The id of the object you wish to update a counter on or an Array of ids.
    # * +counters+ - An Array of Hashes containing the names of the fields
    #   to update as keys and the amount to update the field by as values.
    #
    # ==== Examples
    #
    #   # For the Post with id of 5, decrement the comment_count by 1, and
    #   # increment the action_count by 1
    #   Post.update_counters 5, :comment_count => -1, :action_count => 1
    #   # Executes the following SQL:
    #   # UPDATE posts
    #   #    SET comment_count = COALESCE(comment_count, 0) - 1,
    #   #        action_count = COALESCE(action_count, 0) + 1
    #   #  WHERE id = 5
    #
    #   # For the Posts with id of 10 and 15, increment the comment_count by 1
    #   Post.update_counters [10, 15], :comment_count => 1
    #   # Executes the following SQL:
    #   # UPDATE posts
    #   #    SET comment_count = COALESCE(comment_count, 0) + 1
    #   #  WHERE id IN (10, 15)
    def update_counters(id, counters)
      updates = counters.map do |counter_name, value|
        operator = value < 0 ? '-' : '+'
        quoted_column = connection.quote_column_name(counter_name)
        "#{quoted_column} = COALESCE(#{quoted_column}, 0) #{operator} #{value.abs}"
      end

      IdentityMap.remove_by_id(symbolized_base_class, id) if IdentityMap.enabled?

      update_all(updates.join(', '), primary_key => id )
    end

    # Increment a number field by one, usually representing a count.
    #
    # This is used for caching aggregate values, so that they don't need to be computed every time.
    # For example, a DiscussionBoard may cache post_count and comment_count otherwise every time the board is
    # shown it would have to run an SQL query to find how many posts and comments there are.
    #
    # ==== Parameters
    #
    # * +counter_name+ - The name of the field that should be incremented.
    # * +id+ - The id of the object that should be incremented.
    #
    # ==== Examples
    #
    #   # Increment the post_count column for the record with an id of 5
    #   DiscussionBoard.increment_counter(:post_count, 5)
    def increment_counter(counter_name, id)
      update_counters(id, counter_name => 1)
    end

    # Decrement a number field by one, usually representing a count.
    #
    # This works the same as increment_counter but reduces the column value by 1 instead of increasing it.
    #
    # ==== Parameters
    #
    # * +counter_name+ - The name of the field that should be decremented.
    # * +id+ - The id of the object that should be decremented.
    #
    # ==== Examples
    #
    #   # Decrement the post_count column for the record with an id of 5
    #   DiscussionBoard.decrement_counter(:post_count, 5)
    def decrement_counter(counter_name, id)
      update_counters(id, counter_name => -1)
    end
  end
end
module ActiveRecord

  # = Active Record Dynamic Finder Match
  #
  # Refer to ActiveRecord::Base documentation for Dynamic attribute-based finders for detailed info
  #
  class DynamicFinderMatch
    def self.match(method)
      finder       = :first
      bang         = false
      instantiator = nil

      case method.to_s
      when /^find_(all_|last_)?by_([_a-zA-Z]\w*)$/
        finder = :last if $1 == 'last_'
        finder = :all if $1 == 'all_'
        names = $2
      when /^find_by_([_a-zA-Z]\w*)\!$/
        bang = true
        names = $1
      when /^find_or_create_by_([_a-zA-Z]\w*)\!$/
        bang = true
        instantiator = :create
        names = $1
      when /^find_or_(initialize|create)_by_([_a-zA-Z]\w*)$/
        instantiator = $1 == 'initialize' ? :new : :create
        names = $2
      else
        return nil
      end

      new(finder, instantiator, bang, names.split('_and_'))
    end

    def initialize(finder, instantiator, bang, attribute_names)
      @finder          = finder
      @instantiator    = instantiator
      @bang            = bang
      @attribute_names = attribute_names
    end

    attr_reader :finder, :attribute_names, :instantiator

    def finder?
      @finder && !@instantiator
    end

    def instantiator?
      @finder == :first && @instantiator
    end

    def creator?
      @finder == :first && @instantiator == :create
    end

    def bang?
      @bang
    end

    def save_record?
      @instantiator == :create
    end

    def save_method
      bang? ? :save! : :save
    end
  end
end
module ActiveRecord
  module DynamicMatchers
    def respond_to?(method_id, include_private = false)
      if match = DynamicFinderMatch.match(method_id)
        return true if all_attributes_exists?(match.attribute_names)
      elsif match = DynamicScopeMatch.match(method_id)
        return true if all_attributes_exists?(match.attribute_names)
      end

      super
    end

    private

    # Enables dynamic finders like <tt>User.find_by_user_name(user_name)</tt> and
    # <tt>User.scoped_by_user_name(user_name). Refer to Dynamic attribute-based finders
    # section at the top of this file for more detailed information.
    #
    # It's even possible to use all the additional parameters to +find+. For example, the
    # full interface for +find_all_by_amount+ is actually <tt>find_all_by_amount(amount, options)</tt>.
    #
    # Each dynamic finder using <tt>scoped_by_*</tt> is also defined in the class after it
    # is first invoked, so that future attempts to use it do not run through method_missing.
    def method_missing(method_id, *arguments, &block)
      if match = (DynamicFinderMatch.match(method_id) || DynamicScopeMatch.match(method_id))
        attribute_names = match.attribute_names
        super unless all_attributes_exists?(attribute_names)
        if !(match.is_a?(DynamicFinderMatch) && match.instantiator? && arguments.first.is_a?(Hash)) && arguments.size < attribute_names.size
          method_trace = "#{__FILE__}:#{__LINE__}:in `#{method_id}'"
          backtrace = [method_trace] + caller
          raise ArgumentError, "wrong number of arguments (#{arguments.size} for #{attribute_names.size})", backtrace
        end
        if match.respond_to?(:scope?) && match.scope?
          self.class_eval <<-METHOD, __FILE__, __LINE__ + 1
            def self.#{method_id}(*args)                                    # def self.scoped_by_user_name_and_password(*args)
              attributes = Hash[[:#{attribute_names.join(',:')}].zip(args)] #   attributes = Hash[[:user_name, :password].zip(args)]
                                                                            #
              scoped(:conditions => attributes)                             #   scoped(:conditions => attributes)
            end                                                             # end
          METHOD
          send(method_id, *arguments)
        elsif match.finder?
          options = if arguments.length > attribute_names.size
                      arguments.extract_options!
                    else
                      {}
                    end

          relation = options.any? ? scoped(options) : scoped
          relation.send :find_by_attributes, match, attribute_names, *arguments, &block
        elsif match.instantiator?
          scoped.send :find_or_instantiator_by_attributes, match, attribute_names, *arguments, &block
        end
      else
        super
      end
    end

    # Similar in purpose to +expand_hash_conditions_for_aggregates+.
    def expand_attribute_names_for_aggregates(attribute_names)
      attribute_names.map { |attribute_name|
        unless (aggregation = reflect_on_aggregation(attribute_name.to_sym)).nil?
          aggregate_mapping(aggregation).map do |field_attr, _|
            field_attr.to_sym
          end
        else
          attribute_name.to_sym
        end
      }.flatten
    end

    def all_attributes_exists?(attribute_names)
      (expand_attribute_names_for_aggregates(attribute_names) -
       column_methods_hash.keys).empty?
    end

    def aggregate_mapping(reflection)
      mapping = reflection.options[:mapping] || [reflection.name, reflection.name]
      mapping.first.is_a?(Array) ? mapping : [mapping]
    end


  end
end
module ActiveRecord

  # = Active Record Dynamic Scope Match
  #
  # Provides dynamic attribute-based scopes such as <tt>scoped_by_price(4.99)</tt>
  # if, for example, the <tt>Product</tt> has an attribute with that name. You can
  # chain more <tt>scoped_by_* </tt> methods after the other. It acts like a named
  # scope except that it's dynamic.
  class DynamicScopeMatch
    def self.match(method)
      return unless method.to_s =~ /^scoped_by_([_a-zA-Z]\w*)$/
      new(true, $1 && $1.split('_and_'))
    end

    def initialize(scope, attribute_names)
      @scope           = scope
      @attribute_names = attribute_names
    end

    attr_reader :scope, :attribute_names
    alias :scope? :scope
  end
end
module ActiveRecord

  # = Active Record Errors
  #
  # Generic Active Record exception class.
  class ActiveRecordError < StandardError
  end

  # Raised when the single-table inheritance mechanism fails to locate the subclass
  # (for example due to improper usage of column that +inheritance_column+ points to).
  class SubclassNotFound < ActiveRecordError #:nodoc:
  end

  # Raised when an object assigned to an association has an incorrect type.
  #
  #   class Ticket < ActiveRecord::Base
  #     has_many :patches
  #   end
  #
  #   class Patch < ActiveRecord::Base
  #     belongs_to :ticket
  #   end
  #
  #   # Comments are not patches, this assignment raises AssociationTypeMismatch.
  #   @ticket.patches << Comment.new(:content => "Please attach tests to your patch.")
  class AssociationTypeMismatch < ActiveRecordError
  end

  # Raised when unserialized object's type mismatches one specified for serializable field.
  class SerializationTypeMismatch < ActiveRecordError
  end

  # Raised when adapter not specified on connection (or configuration file <tt>config/database.yml</tt>
  # misses adapter field).
  class AdapterNotSpecified < ActiveRecordError
  end

  # Raised when Active Record cannot find database adapter specified in <tt>config/database.yml</tt> or programmatically.
  class AdapterNotFound < ActiveRecordError
  end

  # Raised when connection to the database could not been established (for example when <tt>connection=</tt>
  # is given a nil object).
  class ConnectionNotEstablished < ActiveRecordError
  end

  # Raised when Active Record cannot find record by given id or set of ids.
  class RecordNotFound < ActiveRecordError
  end

  # Raised by ActiveRecord::Base.save! and ActiveRecord::Base.create! methods when record cannot be
  # saved because record is invalid.
  class RecordNotSaved < ActiveRecordError
  end

  # Raised when SQL statement cannot be executed by the database (for example, it's often the case for
  # MySQL when Ruby driver used is too old).
  class StatementInvalid < ActiveRecordError
  end

  # Raised when SQL statement is invalid and the application gets a blank result.
  class ThrowResult < ActiveRecordError
  end

  # Parent class for all specific exceptions which wrap database driver exceptions
  # provides access to the original exception also.
  class WrappedDatabaseException < StatementInvalid
    attr_reader :original_exception

    def initialize(message, original_exception)
      super(message)
      @original_exception = original_exception
    end
  end

  # Raised when a record cannot be inserted because it would violate a uniqueness constraint.
  class RecordNotUnique < WrappedDatabaseException
  end

  # Raised when a record cannot be inserted or updated because it references a non-existent record.
  class InvalidForeignKey < WrappedDatabaseException
  end

  # Raised when number of bind variables in statement given to <tt>:condition</tt> key (for example,
  # when using +find+ method)
  # does not match number of expected variables.
  #
  # For example, in
  #
  #   Location.where("lat = ? AND lng = ?", 53.7362)
  #
  # two placeholders are given but only one variable to fill them.
  class PreparedStatementInvalid < ActiveRecordError
  end

  # Raised on attempt to save stale record. Record is stale when it's being saved in another query after
  # instantiation, for example, when two users edit the same wiki page and one starts editing and saves
  # the page before the other.
  #
  # Read more about optimistic locking in ActiveRecord::Locking module RDoc.
  class StaleObjectError < ActiveRecordError
    attr_reader :record, :attempted_action

    def initialize(record, attempted_action)
      @record = record
      @attempted_action = attempted_action
    end

    def message
      "Attempted to #{attempted_action} a stale object: #{record.class.name}"
    end
  end

  # Raised when association is being configured improperly or
  # user tries to use offset and limit together with has_many or has_and_belongs_to_many associations.
  class ConfigurationError < ActiveRecordError
  end

  # Raised on attempt to update record that is instantiated as read only.
  class ReadOnlyRecord < ActiveRecordError
  end

  # ActiveRecord::Transactions::ClassMethods.transaction uses this exception
  # to distinguish a deliberate rollback from other exceptional situations.
  # Normally, raising an exception will cause the +transaction+ method to rollback
  # the database transaction *and* pass on the exception. But if you raise an
  # ActiveRecord::Rollback exception, then the database transaction will be rolled back,
  # without passing on the exception.
  #
  # For example, you could do this in your controller to rollback a transaction:
  #
  #   class BooksController < ActionController::Base
  #     def create
  #       Book.transaction do
  #         book = Book.new(params[:book])
  #         book.save!
  #         if today_is_friday?
  #           # The system must fail on Friday so that our support department
  #           # won't be out of job. We silently rollback this transaction
  #           # without telling the user.
  #           raise ActiveRecord::Rollback, "Call tech support!"
  #         end
  #       end
  #       # ActiveRecord::Rollback is the only exception that won't be passed on
  #       # by ActiveRecord::Base.transaction, so this line will still be reached
  #       # even on Friday.
  #       redirect_to root_url
  #     end
  #   end
  class Rollback < ActiveRecordError
  end

  # Raised when attribute has a name reserved by Active Record (when attribute has name of one of Active Record instance methods).
  class DangerousAttributeError < ActiveRecordError
  end

  # Raised when unknown attributes are supplied via mass assignment.
  class UnknownAttributeError < NoMethodError
  end

  # Raised when an error occurred while doing a mass assignment to an attribute through the
  # <tt>attributes=</tt> method. The exception has an +attribute+ property that is the name of the
  # offending attribute.
  class AttributeAssignmentError < ActiveRecordError
    attr_reader :exception, :attribute
    def initialize(message, exception, attribute)
      @exception = exception
      @attribute = attribute
      @message = message
    end
  end

  # Raised when there are multiple errors while doing a mass assignment through the +attributes+
  # method. The exception has an +errors+ property that contains an array of AttributeAssignmentError
  # objects, each corresponding to the error while assigning to an attribute.
  class MultiparameterAssignmentErrors < ActiveRecordError
    attr_reader :errors
    def initialize(errors)
      @errors = errors
    end
  end

  # Raised when a primary key is needed, but there is not one specified in the schema or model.
  class UnknownPrimaryKey < ActiveRecordError
    attr_reader :model

    def initialize(model)
      @model = model
    end

    def message
      "Unknown primary key for table #{model.table_name} in model #{model}."
    end
  end
end
require 'active_support/core_ext/class/attribute'

module ActiveRecord
  module Explain
    def self.extended(base)
      base.class_eval do
        # If a query takes longer than these many seconds we log its query plan
        # automatically. nil disables this feature.
        class_attribute :auto_explain_threshold_in_seconds, :instance_writer => false
        self.auto_explain_threshold_in_seconds = nil
      end
    end

    # If auto explain is enabled, this method triggers EXPLAIN logging for the
    # queries triggered by the block if it takes more than the threshold as a
    # whole. That is, the threshold is not checked against each individual
    # query, but against the duration of the entire block. This approach is
    # convenient for relations.
    #
    # The available_queries_for_explain thread variable collects the queries
    # to be explained. If the value is nil, it means queries are not being
    # currently collected. A false value indicates collecting is turned
    # off. Otherwise it is an array of queries.
    def logging_query_plan # :nodoc:
      return yield unless logger

      threshold = auto_explain_threshold_in_seconds
      current   = Thread.current
      if threshold && current[:available_queries_for_explain].nil?
        begin
          queries = current[:available_queries_for_explain] = []
          start = Time.now
          result = yield
          logger.warn(exec_explain(queries)) if Time.now - start > threshold
          result
        ensure
          current[:available_queries_for_explain] = nil
        end
      else
        yield
      end
    end

    # Relation#explain needs to be able to collect the queries regardless of
    # whether auto explain is enabled. This method serves that purpose.
    def collecting_queries_for_explain # :nodoc:
      current = Thread.current
      original, current[:available_queries_for_explain] = current[:available_queries_for_explain], []
      return yield, current[:available_queries_for_explain]
    ensure
      # Note that the return value above does not depend on this assigment.
      current[:available_queries_for_explain] = original
    end

    # Makes the adapter execute EXPLAIN for the tuples of queries and bindings.
    # Returns a formatted string ready to be logged.
    def exec_explain(queries) # :nodoc:
      queries && queries.map do |sql, bind|
        [].tap do |msg|
          msg << "EXPLAIN for: #{sql}"
          unless bind.empty?
            bind_msg = bind.map {|col, val| [col.name, val]}.inspect
            msg.last << " #{bind_msg}"
          end
          msg << connection.explain(sql, bind)
        end.join("\n")
      end.join("\n")
    end

    # Silences automatic EXPLAIN logging for the duration of the block.
    #
    # This has high priority, no EXPLAINs will be run even if downwards
    # the threshold is set to 0.
    #
    # As the name of the method suggests this only applies to automatic
    # EXPLAINs, manual calls to +ActiveRecord::Relation#explain+ run.
    def silence_auto_explain
      current = Thread.current
      original, current[:available_queries_for_explain] = current[:available_queries_for_explain], false
      yield
    ensure
      current[:available_queries_for_explain] = original
    end
  end
end
require 'active_support/notifications'

module ActiveRecord
  class ExplainSubscriber # :nodoc:
    def call(*args)
      if queries = Thread.current[:available_queries_for_explain]
        payload = args.last
        queries << payload.values_at(:sql, :binds) unless ignore_payload?(payload)
      end
    end

    # SCHEMA queries cannot be EXPLAINed, also we do not want to run EXPLAIN on
    # our own EXPLAINs now matter how loopingly beautiful that would be.
    #
    # On the other hand, we want to monitor the performance of our real database
    # queries, not the performance of the access to the query cache.
    IGNORED_PAYLOADS = %w(SCHEMA EXPLAIN CACHE)
    EXPLAINED_SQLS = /\A\s*(select|update|delete|insert)/i
    def ignore_payload?(payload)
      payload[:exception] || IGNORED_PAYLOADS.include?(payload[:name]) || payload[:sql] !~ EXPLAINED_SQLS
    end

    ActiveSupport::Notifications.subscribe("sql.active_record", new)
  end
end
begin
  require 'psych'
rescue LoadError
end

require 'erb'
require 'yaml'

module ActiveRecord
  class Fixtures
    class File
      include Enumerable

      ##
      # Open a fixture file named +file+.  When called with a block, the block
      # is called with the filehandle and the filehandle is automatically closed
      # when the block finishes.
      def self.open(file)
        x = new file
        block_given? ? yield(x) : x
      end

      def initialize(file)
        @file = file
        @rows = nil
      end

      def each(&block)
        rows.each(&block)
      end

      RESCUE_ERRORS = [ ArgumentError ] # :nodoc:

      private
      if defined?(Psych) && defined?(Psych::SyntaxError)
        RESCUE_ERRORS << Psych::SyntaxError
      end

      def rows
        return @rows if @rows

        begin
          data = YAML.load(render(IO.read(@file)))
        rescue *RESCUE_ERRORS => error
          raise Fixture::FormatError, "a YAML error occurred parsing #{@file}. Please note that YAML must be consistently indented using spaces. Tabs are not allowed. Please have a look at http://www.yaml.org/faq.html\nThe exact error was:\n  #{error.class}: #{error}", error.backtrace
        end
        @rows = data ? validate(data).to_a : []
      end

      def render(content)
        ERB.new(content).result
      end

      # Validate our unmarshalled data.
      def validate(data)
        unless Hash === data || YAML::Omap === data
          raise Fixture::FormatError, 'fixture is not a hash'
        end

        raise Fixture::FormatError unless data.all? { |name, row| Hash === row }
        data
      end
    end
  end
end
require 'erb'

begin
  require 'psych'
rescue LoadError
end

require 'yaml'
require 'zlib'
require 'active_support/dependencies'
require 'active_support/core_ext/array/wrap'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/logger'
require 'active_support/ordered_hash'
require 'active_record/fixtures/file'

if defined? ActiveRecord
  class FixtureClassNotFound < ActiveRecord::ActiveRecordError #:nodoc:
  end
else
  class FixtureClassNotFound < StandardError #:nodoc:
  end
end

module ActiveRecord
  # \Fixtures are a way of organizing data that you want to test against; in short, sample data.
  #
  # They are stored in YAML files, one file per model, which are placed in the directory
  # appointed by <tt>ActiveSupport::TestCase.fixture_path=(path)</tt> (this is automatically
  # configured for Rails, so you can just put your files in <tt><your-rails-app>/test/fixtures/</tt>).
  # The fixture file ends with the <tt>.yml</tt> file extension (Rails example:
  # <tt><your-rails-app>/test/fixtures/web_sites.yml</tt>). The format of a fixture file looks
  # like this:
  #
  #   rubyonrails:
  #     id: 1
  #     name: Ruby on Rails
  #     url: http://www.rubyonrails.org
  #
  #   google:
  #     id: 2
  #     name: Google
  #     url: http://www.google.com
  #
  # This fixture file includes two fixtures. Each YAML fixture (ie. record) is given a name and
  # is followed by an indented list of key/value pairs in the "key: value" format. Records are
  # separated by a blank line for your viewing pleasure.
  #
  # Note that fixtures are unordered. If you want ordered fixtures, use the omap YAML type.
  # See http://yaml.org/type/omap.html
  # for the specification. You will need ordered fixtures when you have foreign key constraints
  # on keys in the same table. This is commonly needed for tree structures. Example:
  #
  #    --- !omap
  #    - parent:
  #        id:         1
  #        parent_id:  NULL
  #        title:      Parent
  #    - child:
  #        id:         2
  #        parent_id:  1
  #        title:      Child
  #
  # = Using Fixtures in Test Cases
  #
  # Since fixtures are a testing construct, we use them in our unit and functional tests. There
  # are two ways to use the fixtures, but first let's take a look at a sample unit test:
  #
  #   require 'test_helper'
  #
  #   class WebSiteTest < ActiveSupport::TestCase
  #     test "web_site_count" do
  #       assert_equal 2, WebSite.count
  #     end
  #   end
  #
  # By default, <tt>test_helper.rb</tt> will load all of your fixtures into your test database,
  # so this test will succeed.
  #
  # The testing environment will automatically load the all fixtures into the database before each
  # test. To ensure consistent data, the environment deletes the fixtures before running the load.
  #
  # In addition to being available in the database, the fixture's data may also be accessed by
  # using a special dynamic method, which has the same name as the model, and accepts the
  # name of the fixture to instantiate:
  #
  #   test "find" do
  #     assert_equal "Ruby on Rails", web_sites(:rubyonrails).name
  #   end
  #
  # Alternatively, you may enable auto-instantiation of the fixture data. For instance, take the
  # following tests:
  #
  #   test "find_alt_method_1" do
  #     assert_equal "Ruby on Rails", @web_sites['rubyonrails']['name']
  #   end
  #
  #   test "find_alt_method_2" do
  #     assert_equal "Ruby on Rails", @rubyonrails.news
  #   end
  #
  # In order to use these methods to access fixtured data within your testcases, you must specify one of the
  # following in your <tt>ActiveSupport::TestCase</tt>-derived class:
  #
  # - to fully enable instantiated fixtures (enable alternate methods #1 and #2 above)
  #     self.use_instantiated_fixtures = true
  #
  # - create only the hash for the fixtures, do not 'find' each instance (enable alternate method #1 only)
  #     self.use_instantiated_fixtures = :no_instances
  #
  # Using either of these alternate methods incurs a performance hit, as the fixtured data must be fully
  # traversed in the database to create the fixture hash and/or instance variables. This is expensive for
  # large sets of fixtured data.
  #
  # = Dynamic fixtures with ERB
  #
  # Some times you don't care about the content of the fixtures as much as you care about the volume.
  # In these cases, you can mix ERB in with your YAML fixtures to create a bunch of fixtures for load
  # testing, like:
  #
  #   <% 1.upto(1000) do |i| %>
  #   fix_<%= i %>:
  #     id: <%= i %>
  #     name: guy_<%= 1 %>
  #   <% end %>
  #
  # This will create 1000 very simple fixtures.
  #
  # Using ERB, you can also inject dynamic values into your fixtures with inserts like
  # <tt><%= Date.today.strftime("%Y-%m-%d") %></tt>.
  # This is however a feature to be used with some caution. The point of fixtures are that they're
  # stable units of predictable sample data. If you feel that you need to inject dynamic values, then
  # perhaps you should reexamine whether your application is properly testable. Hence, dynamic values
  # in fixtures are to be considered a code smell.
  #
  # = Transactional Fixtures
  #
  # Test cases can use begin+rollback to isolate their changes to the database instead of having to
  # delete+insert for every test case.
  #
  #   class FooTest < ActiveSupport::TestCase
  #     self.use_transactional_fixtures = true
  #
  #     test "godzilla" do
  #       assert !Foo.all.empty?
  #       Foo.destroy_all
  #       assert Foo.all.empty?
  #     end
  #
  #     test "godzilla aftermath" do
  #       assert !Foo.all.empty?
  #     end
  #   end
  #
  # If you preload your test database with all fixture data (probably in the rake task) and use
  # transactional fixtures, then you may omit all fixtures declarations in your test cases since
  # all the data's already there and every case rolls back its changes.
  #
  # In order to use instantiated fixtures with preloaded data, set +self.pre_loaded_fixtures+ to
  # true. This will provide access to fixture data for every table that has been loaded through
  # fixtures (depending on the value of +use_instantiated_fixtures+).
  #
  # When *not* to use transactional fixtures:
  #
  # 1. You're testing whether a transaction works correctly. Nested transactions don't commit until
  #    all parent transactions commit, particularly, the fixtures transaction which is begun in setup
  #    and rolled back in teardown. Thus, you won't be able to verify
  #    the results of your transaction until Active Record supports nested transactions or savepoints (in progress).
  # 2. Your database does not support transactions. Every Active Record database supports transactions except MySQL MyISAM.
  #    Use InnoDB, MaxDB, or NDB instead.
  #
  # = Advanced Fixtures
  #
  # Fixtures that don't specify an ID get some extra features:
  #
  # * Stable, autogenerated IDs
  # * Label references for associations (belongs_to, has_one, has_many)
  # * HABTM associations as inline lists
  # * Autofilled timestamp columns
  # * Fixture label interpolation
  # * Support for YAML defaults
  #
  # == Stable, Autogenerated IDs
  #
  # Here, have a monkey fixture:
  #
  #   george:
  #     id: 1
  #     name: George the Monkey
  #
  #   reginald:
  #     id: 2
  #     name: Reginald the Pirate
  #
  # Each of these fixtures has two unique identifiers: one for the database
  # and one for the humans. Why don't we generate the primary key instead?
  # Hashing each fixture's label yields a consistent ID:
  #
  #   george: # generated id: 503576764
  #     name: George the Monkey
  #
  #   reginald: # generated id: 324201669
  #     name: Reginald the Pirate
  #
  # Active Record looks at the fixture's model class, discovers the correct
  # primary key, and generates it right before inserting the fixture
  # into the database.
  #
  # The generated ID for a given label is constant, so we can discover
  # any fixture's ID without loading anything, as long as we know the label.
  #
  # == Label references for associations (belongs_to, has_one, has_many)
  #
  # Specifying foreign keys in fixtures can be very fragile, not to
  # mention difficult to read. Since Active Record can figure out the ID of
  # any fixture from its label, you can specify FK's by label instead of ID.
  #
  # === belongs_to
  #
  # Let's break out some more monkeys and pirates.
  #
  #   ### in pirates.yml
  #
  #   reginald:
  #     id: 1
  #     name: Reginald the Pirate
  #     monkey_id: 1
  #
  #   ### in monkeys.yml
  #
  #   george:
  #     id: 1
  #     name: George the Monkey
  #     pirate_id: 1
  #
  # Add a few more monkeys and pirates and break this into multiple files,
  # and it gets pretty hard to keep track of what's going on. Let's
  # use labels instead of IDs:
  #
  #   ### in pirates.yml
  #
  #   reginald:
  #     name: Reginald the Pirate
  #     monkey: george
  #
  #   ### in monkeys.yml
  #
  #   george:
  #     name: George the Monkey
  #     pirate: reginald
  #
  # Pow! All is made clear. Active Record reflects on the fixture's model class,
  # finds all the +belongs_to+ associations, and allows you to specify
  # a target *label* for the *association* (monkey: george) rather than
  # a target *id* for the *FK* (<tt>monkey_id: 1</tt>).
  #
  # ==== Polymorphic belongs_to
  #
  # Supporting polymorphic relationships is a little bit more complicated, since
  # Active Record needs to know what type your association is pointing at. Something
  # like this should look familiar:
  #
  #   ### in fruit.rb
  #
  #   belongs_to :eater, :polymorphic => true
  #
  #   ### in fruits.yml
  #
  #   apple:
  #     id: 1
  #     name: apple
  #     eater_id: 1
  #     eater_type: Monkey
  #
  # Can we do better? You bet!
  #
  #   apple:
  #     eater: george (Monkey)
  #
  # Just provide the polymorphic target type and Active Record will take care of the rest.
  #
  # === has_and_belongs_to_many
  #
  # Time to give our monkey some fruit.
  #
  #   ### in monkeys.yml
  #
  #   george:
  #     id: 1
  #     name: George the Monkey
  #
  #   ### in fruits.yml
  #
  #   apple:
  #     id: 1
  #     name: apple
  #
  #   orange:
  #     id: 2
  #     name: orange
  #
  #   grape:
  #     id: 3
  #     name: grape
  #
  #   ### in fruits_monkeys.yml
  #
  #   apple_george:
  #     fruit_id: 1
  #     monkey_id: 1
  #
  #   orange_george:
  #     fruit_id: 2
  #     monkey_id: 1
  #
  #   grape_george:
  #     fruit_id: 3
  #     monkey_id: 1
  #
  # Let's make the HABTM fixture go away.
  #
  #   ### in monkeys.yml
  #
  #   george:
  #     id: 1
  #     name: George the Monkey
  #     fruits: apple, orange, grape
  #
  #   ### in fruits.yml
  #
  #   apple:
  #     name: apple
  #
  #   orange:
  #     name: orange
  #
  #   grape:
  #     name: grape
  #
  # Zap! No more fruits_monkeys.yml file. We've specified the list of fruits
  # on George's fixture, but we could've just as easily specified a list
  # of monkeys on each fruit. As with +belongs_to+, Active Record reflects on
  # the fixture's model class and discovers the +has_and_belongs_to_many+
  # associations.
  #
  # == Autofilled Timestamp Columns
  #
  # If your table/model specifies any of Active Record's
  # standard timestamp columns (+created_at+, +created_on+, +updated_at+, +updated_on+),
  # they will automatically be set to <tt>Time.now</tt>.
  #
  # If you've set specific values, they'll be left alone.
  #
  # == Fixture label interpolation
  #
  # The label of the current fixture is always available as a column value:
  #
  #   geeksomnia:
  #     name: Geeksomnia's Account
  #     subdomain: $LABEL
  #
  # Also, sometimes (like when porting older join table fixtures) you'll need
  # to be able to get a hold of the identifier for a given label. ERB
  # to the rescue:
  #
  #   george_reginald:
  #     monkey_id: <%= ActiveRecord::Fixtures.identify(:reginald) %>
  #     pirate_id: <%= ActiveRecord::Fixtures.identify(:george) %>
  #
  # == Support for YAML defaults
  #
  # You probably already know how to use YAML to set and reuse defaults in
  # your <tt>database.yml</tt> file. You can use the same technique in your fixtures:
  #
  #   DEFAULTS: &DEFAULTS
  #     created_on: <%= 3.weeks.ago.to_s(:db) %>
  #
  #   first:
  #     name: Smurf
  #     *DEFAULTS
  #
  #   second:
  #     name: Fraggle
  #     *DEFAULTS
  #
  # Any fixture labeled "DEFAULTS" is safely ignored.
  class Fixtures
    MAX_ID = 2 ** 30 - 1

    @@all_cached_fixtures = Hash.new { |h,k| h[k] = {} }

    def self.find_table_name(table_name) # :nodoc:
      ActiveRecord::Base.pluralize_table_names ?
        table_name.to_s.singularize.camelize :
        table_name.to_s.camelize
    end

    def self.reset_cache
      @@all_cached_fixtures.clear
    end

    def self.cache_for_connection(connection)
      @@all_cached_fixtures[connection]
    end

    def self.fixture_is_cached?(connection, table_name)
      cache_for_connection(connection)[table_name]
    end

    def self.cached_fixtures(connection, keys_to_fetch = nil)
      if keys_to_fetch
        cache_for_connection(connection).values_at(*keys_to_fetch)
      else
        cache_for_connection(connection).values
      end
    end

    def self.cache_fixtures(connection, fixtures_map)
      cache_for_connection(connection).update(fixtures_map)
    end

    #--
    # TODO:NOTE: in the next version, the __with_new_arity suffix and
    #   the method with the old arity will be removed.
    #++
    def self.instantiate_fixtures__with_new_arity(object, fixture_set, load_instances = true) # :nodoc:
      if load_instances
        fixture_set.each do |fixture_name, fixture|
          begin
            object.instance_variable_set "@#{fixture_name}", fixture.find
          rescue FixtureClassNotFound
            nil
          end
        end
      end
    end

    # The use with parameters  <tt>(object, fixture_set_name, fixture_set, load_instances = true)</tt>  is deprecated,  +fixture_set_name+  parameter is not used.
    # Use as:
    #
    #   instantiate_fixtures(object, fixture_set, load_instances = true)
    def self.instantiate_fixtures(object, fixture_set, load_instances = true, rails_3_2_compatibility_argument = true)
      unless load_instances == true || load_instances == false
        ActiveSupport::Deprecation.warn(
          "ActiveRecord::Fixtures.instantiate_fixtures with parameters (object, fixture_set_name, fixture_set, load_instances = true) is deprecated and shall be removed from future releases.  Use it with parameters (object, fixture_set, load_instances = true) instead (skip fixture_set_name).",
          caller)
        fixture_set = load_instances
        load_instances = rails_3_2_compatibility_argument
      end
      instantiate_fixtures__with_new_arity(object, fixture_set, load_instances)
    end

    def self.instantiate_all_loaded_fixtures(object, load_instances = true)
      all_loaded_fixtures.each_value do |fixture_set|
        ActiveRecord::Fixtures.instantiate_fixtures(object, fixture_set, load_instances)
      end
    end

    cattr_accessor :all_loaded_fixtures
    self.all_loaded_fixtures = {}

    def self.create_fixtures(fixtures_directory, table_names, class_names = {})
      table_names = [table_names].flatten.map { |n| n.to_s }
      table_names.each { |n|
        class_names[n.tr('/', '_').to_sym] = n.classify if n.include?('/')
      }

      # FIXME: Apparently JK uses this.
      connection = block_given? ? yield : ActiveRecord::Base.connection

      files_to_read = table_names.reject { |table_name|
        fixture_is_cached?(connection, table_name)
      }

      unless files_to_read.empty?
        connection.disable_referential_integrity do
          fixtures_map = {}

          fixture_files = files_to_read.map do |path|
            table_name = path.tr '/', '_'

            fixtures_map[path] = ActiveRecord::Fixtures.new(
              connection,
              table_name,
              class_names[table_name.to_sym] || table_name.classify,
              ::File.join(fixtures_directory, path))
          end

          all_loaded_fixtures.update(fixtures_map)

          connection.transaction(:requires_new => true) do
            fixture_files.each do |ff|
              conn = ff.model_class.respond_to?(:connection) ? ff.model_class.connection : connection
              table_rows = ff.table_rows

              table_rows.keys.each do |table|
                conn.delete "DELETE FROM #{conn.quote_table_name(table)}", 'Fixture Delete'
              end

              table_rows.each do |table_name,rows|
                rows.each do |row|
                  conn.insert_fixture(row, table_name)
                end
              end
            end

            # Cap primary key sequences to max(pk).
            if connection.respond_to?(:reset_pk_sequence!)
              table_names.each do |table_name|
                connection.reset_pk_sequence!(table_name.tr('/', '_'))
              end
            end
          end

          cache_fixtures(connection, fixtures_map)
        end
      end
      cached_fixtures(connection, table_names)
    end

    # Returns a consistent, platform-independent identifier for +label+.
    # Identifiers are positive integers less than 2^32.
    def self.identify(label)
      Zlib.crc32(label.to_s) % MAX_ID
    end

    attr_reader :table_name, :name, :fixtures, :model_class

    def initialize(connection, table_name, class_name, fixture_path)
      @connection   = connection
      @table_name   = table_name
      @fixture_path = fixture_path
      @name         = table_name # preserve fixture base name
      @class_name   = class_name

      @fixtures     = ActiveSupport::OrderedHash.new
      @table_name   = "#{ActiveRecord::Base.table_name_prefix}#{@table_name}#{ActiveRecord::Base.table_name_suffix}"

      # Should be an AR::Base type class
      if class_name.is_a?(Class)
        @table_name   = class_name.table_name
        @connection   = class_name.connection
        @model_class  = class_name
      else
        @model_class  = class_name.constantize rescue nil
      end

      read_fixture_files
    end

    def [](x)
      fixtures[x]
    end

    def []=(k,v)
      fixtures[k] = v
    end

    def each(&block)
      fixtures.each(&block)
    end

    def size
      fixtures.size
    end

    # Return a hash of rows to be inserted. The key is the table, the value is
    # a list of rows to insert to that table.
    def table_rows
      now = ActiveRecord::Base.default_timezone == :utc ? Time.now.utc : Time.now
      now = now.to_s(:db)

      # allow a standard key to be used for doing defaults in YAML
      fixtures.delete('DEFAULTS')

      # track any join tables we need to insert later
      rows = Hash.new { |h,table| h[table] = [] }

      rows[table_name] = fixtures.map do |label, fixture|
        row = fixture.to_hash

        if model_class && model_class < ActiveRecord::Base
          # fill in timestamp columns if they aren't specified and the model is set to record_timestamps
          if model_class.record_timestamps
            timestamp_column_names.each do |name|
              row[name] = now unless row.key?(name)
            end
          end

          # interpolate the fixture label
          row.each do |key, value|
            row[key] = label if value == "$LABEL"
          end

          # generate a primary key if necessary
          if has_primary_key_column? && !row.include?(primary_key_name)
            row[primary_key_name] = ActiveRecord::Fixtures.identify(label)
          end

          # If STI is used, find the correct subclass for association reflection
          reflection_class =
            if row.include?(inheritance_column_name)
              row[inheritance_column_name].constantize rescue model_class
            else
              model_class
            end

          reflection_class.reflect_on_all_associations.each do |association|
            case association.macro
            when :belongs_to
              # Do not replace association name with association foreign key if they are named the same
              fk_name = (association.options[:foreign_key] || "#{association.name}_id").to_s

              if association.name.to_s != fk_name && value = row.delete(association.name.to_s)
                if association.options[:polymorphic] && value.sub!(/\s*\(([^\)]*)\)\s*$/, "")
                  # support polymorphic belongs_to as "label (Type)"
                  row[association.foreign_type] = $1
                end

                row[fk_name] = ActiveRecord::Fixtures.identify(value)
              end
            when :has_and_belongs_to_many
              if (targets = row.delete(association.name.to_s))
                targets = targets.is_a?(Array) ? targets : targets.split(/\s*,\s*/)
                table_name = association.options[:join_table]
                rows[table_name].concat targets.map { |target|
                  { association.foreign_key             => row[primary_key_name],
                    association.association_foreign_key => ActiveRecord::Fixtures.identify(target) }
                }
              end
            end
          end
        end

        row
      end
      rows
    end

    private
      def primary_key_name
        @primary_key_name ||= model_class && model_class.primary_key
      end

      def has_primary_key_column?
        @has_primary_key_column ||= primary_key_name &&
          model_class.columns.any? { |c| c.name == primary_key_name }
      end

      def timestamp_column_names
        @timestamp_column_names ||=
          %w(created_at created_on updated_at updated_on) & column_names
      end

      def inheritance_column_name
        @inheritance_column_name ||= model_class && model_class.inheritance_column
      end

      def column_names
        @column_names ||= @connection.columns(@table_name).collect { |c| c.name }
      end

      def read_fixture_files
        yaml_files = Dir["#{@fixture_path}/**/*.yml"].select { |f|
          ::File.file?(f)
        } + [yaml_file_path]

        yaml_files.each do |file|
          Fixtures::File.open(file) do |fh|
            fh.each do |name, row|
              fixtures[name] = ActiveRecord::Fixture.new(row, model_class)
            end
          end
        end
      end

      def yaml_file_path
        "#{@fixture_path}.yml"
      end

  end

  class Fixture #:nodoc:
    include Enumerable

    class FixtureError < StandardError #:nodoc:
    end

    class FormatError < FixtureError #:nodoc:
    end

    attr_reader :model_class, :fixture

    def initialize(fixture, model_class)
      @fixture     = fixture
      @model_class = model_class
    end

    def class_name
      model_class.name if model_class
    end

    def each
      fixture.each { |item| yield item }
    end

    def [](key)
      fixture[key]
    end

    alias :to_hash :fixture

    def find
      if model_class
        model_class.find(fixture[model_class.primary_key])
      else
        raise FixtureClassNotFound, "No class attached to find."
      end
    end
  end
end

module ActiveRecord
  module TestFixtures
    extend ActiveSupport::Concern

    included do
      setup :setup_fixtures
      teardown :teardown_fixtures

      class_attribute :fixture_path
      class_attribute :fixture_table_names
      class_attribute :fixture_class_names
      class_attribute :use_transactional_fixtures
      class_attribute :use_instantiated_fixtures   # true, false, or :no_instances
      class_attribute :pre_loaded_fixtures

      self.fixture_table_names = []
      self.use_transactional_fixtures = true
      self.use_instantiated_fixtures = false
      self.pre_loaded_fixtures = false

      self.fixture_class_names = Hash.new do |h, table_name|
        h[table_name] = ActiveRecord::Fixtures.find_table_name(table_name)
      end
    end

    module ClassMethods
      def set_fixture_class(class_names = {})
        self.fixture_class_names = self.fixture_class_names.merge(class_names)
      end

      def fixtures(*fixture_names)
        if fixture_names.first == :all
          fixture_names = Dir["#{fixture_path}/**/*.{yml}"]
          fixture_names.map! { |f| f[(fixture_path.size + 1)..-5] }
        else
          fixture_names = fixture_names.flatten.map { |n| n.to_s }
        end

        self.fixture_table_names |= fixture_names
        require_fixture_classes(fixture_names)
        setup_fixture_accessors(fixture_names)
      end

      def try_to_load_dependency(file_name)
        require_dependency file_name
      rescue LoadError => e
        # Let's hope the developer has included it himself

        # Let's warn in case this is a subdependency, otherwise
        # subdependency error messages are totally cryptic
        if ActiveRecord::Base.logger
          ActiveRecord::Base.logger.warn("Unable to load #{file_name}, underlying cause #{e.message} \n\n #{e.backtrace.join("\n")}")
        end
      end

      def require_fixture_classes(fixture_names = nil)
        (fixture_names || fixture_table_names).each do |fixture_name|
          file_name = fixture_name.to_s
          file_name = file_name.singularize if ActiveRecord::Base.pluralize_table_names
          try_to_load_dependency(file_name)
        end
      end

      def setup_fixture_accessors(fixture_names = nil)
        fixture_names = Array.wrap(fixture_names || fixture_table_names)
        methods = Module.new do
          fixture_names.each do |fixture_name|
            fixture_name = fixture_name.to_s.tr('./', '_')

            define_method(fixture_name) do |*fixtures|
              force_reload = fixtures.pop if fixtures.last == true || fixtures.last == :reload

              @fixture_cache[fixture_name] ||= {}

              instances = fixtures.map do |fixture|
                @fixture_cache[fixture_name].delete(fixture) if force_reload

                if @loaded_fixtures[fixture_name][fixture.to_s]
                  ActiveRecord::IdentityMap.without do
                    @fixture_cache[fixture_name][fixture] ||= @loaded_fixtures[fixture_name][fixture.to_s].find
                  end
                else
                  raise StandardError, "No fixture with name '#{fixture}' found for table '#{fixture_name}'"
                end
              end

              instances.size == 1 ? instances.first : instances
            end
            private fixture_name
          end
        end
        include methods
      end

      def uses_transaction(*methods)
        @uses_transaction = [] unless defined?(@uses_transaction)
        @uses_transaction.concat methods.map { |m| m.to_s }
      end

      def uses_transaction?(method)
        @uses_transaction = [] unless defined?(@uses_transaction)
        @uses_transaction.include?(method.to_s)
      end
    end

    def run_in_transaction?
      use_transactional_fixtures &&
        !self.class.uses_transaction?(method_name)
    end

    def setup_fixtures
      return unless !ActiveRecord::Base.configurations.blank?

      if pre_loaded_fixtures && !use_transactional_fixtures
        raise RuntimeError, 'pre_loaded_fixtures requires use_transactional_fixtures'
      end

      @fixture_cache = {}
      @fixture_connections = []
      @@already_loaded_fixtures ||= {}

      # Load fixtures once and begin transaction.
      if run_in_transaction?
        if @@already_loaded_fixtures[self.class]
          @loaded_fixtures = @@already_loaded_fixtures[self.class]
        else
          @loaded_fixtures = load_fixtures
          @@already_loaded_fixtures[self.class] = @loaded_fixtures
        end
        @fixture_connections = enlist_fixture_connections
        @fixture_connections.each do |connection|
          connection.increment_open_transactions
          connection.transaction_joinable = false
          connection.begin_db_transaction
        end
      # Load fixtures for every test.
      else
        ActiveRecord::Fixtures.reset_cache
        @@already_loaded_fixtures[self.class] = nil
        @loaded_fixtures = load_fixtures
      end

      # Instantiate fixtures for every test if requested.
      instantiate_fixtures if use_instantiated_fixtures
    end

    def teardown_fixtures
      return unless defined?(ActiveRecord) && !ActiveRecord::Base.configurations.blank?

      unless run_in_transaction?
        ActiveRecord::Fixtures.reset_cache
      end

      # Rollback changes if a transaction is active.
      if run_in_transaction?
        @fixture_connections.each do |connection|
          if connection.open_transactions != 0
            connection.rollback_db_transaction
            connection.decrement_open_transactions
          end
        end
        @fixture_connections.clear
      end
      ActiveRecord::Base.clear_active_connections!
    end

    def enlist_fixture_connections
      ActiveRecord::Base.connection_handler.connection_pools.values.map(&:connection)
    end

    private
      def load_fixtures
        fixtures = ActiveRecord::Fixtures.create_fixtures(fixture_path, fixture_table_names, fixture_class_names)
        Hash[fixtures.map { |f| [f.name, f] }]
      end

      # for pre_loaded_fixtures, only require the classes once. huge speed improvement
      @@required_fixture_classes = false

      def instantiate_fixtures
        if pre_loaded_fixtures
          raise RuntimeError, 'Load fixtures before instantiating them.' if ActiveRecord::Fixtures.all_loaded_fixtures.empty?
          unless @@required_fixture_classes
            self.class.require_fixture_classes ActiveRecord::Fixtures.all_loaded_fixtures.keys
            @@required_fixture_classes = true
          end
          ActiveRecord::Fixtures.instantiate_all_loaded_fixtures(self, load_instances?)
        else
          raise RuntimeError, 'Load fixtures before instantiating them.' if @loaded_fixtures.nil?
          @loaded_fixtures.each_value do |fixture_set|
            ActiveRecord::Fixtures.instantiate_fixtures(self, fixture_set, load_instances?)
          end
        end
      end

      def load_instances?
        use_instantiated_fixtures != :no_instances
      end
  end
end
module ActiveRecord
  # = Active Record Identity Map
  #
  # Ensures that each object gets loaded only once by keeping every loaded
  # object in a map. Looks up objects using the map when referring to them.
  #
  # More information on Identity Map pattern:
  #   http://www.martinfowler.com/eaaCatalog/identityMap.html
  #
  # == Configuration
  #
  # In order to enable IdentityMap, set <tt>config.active_record.identity_map = true</tt>
  # in your <tt>config/application.rb</tt> file.
  #
  # IdentityMap is disabled by default and still in development (i.e. use it with care).
  #
  # == Associations
  #
  # Active Record Identity Map does not track associations yet. For example:
  #
  #   comment = @post.comments.first
  #   comment.post = nil
  #   @post.comments.include?(comment) #=> true
  #
  # Ideally, the example above would return false, removing the comment object from the
  # post association when the association is nullified. This may cause side effects, as
  # in the situation below, if Identity Map is enabled:
  #
  #   Post.has_many :comments, :dependent => :destroy
  #
  #   comment = @post.comments.first
  #   comment.post = nil
  #   comment.save
  #   Post.destroy(@post.id)
  #
  # Without using Identity Map, the code above will destroy the @post object leaving
  # the comment object intact. However, once we enable Identity Map, the post loaded
  # by Post.destroy is exactly the same object as the object @post. As the object @post
  # still has the comment object in @post.comments, once Identity Map is enabled, the
  # comment object will be accidently removed.
  #
  # This inconsistency is meant to be fixed in future Rails releases.
  #
  module IdentityMap

    class << self
      def enabled=(flag)
        Thread.current[:identity_map_enabled] = flag
      end

      def enabled
        Thread.current[:identity_map_enabled]
      end
      alias enabled? enabled

      def repository
        Thread.current[:identity_map] ||= Hash.new { |h,k| h[k] = {} }
      end

      def use
        old, self.enabled = enabled, true

        yield if block_given?
      ensure
        self.enabled = old
        clear
      end

      def without
        old, self.enabled = enabled, false

        yield if block_given?
      ensure
        self.enabled = old
      end

      def get(klass, primary_key)
        record = repository[klass.symbolized_sti_name][primary_key]

        if record.is_a?(klass)
          ActiveSupport::Notifications.instrument("identity.active_record",
            :line => "From Identity Map (id: #{primary_key})",
            :name => "#{klass} Loaded",
            :connection_id => object_id)

          record
        else
          nil
        end
      end

      def add(record)
        repository[record.class.symbolized_sti_name][record.id] = record if contain_all_columns?(record)
      end

      def remove(record)
        repository[record.class.symbolized_sti_name].delete(record.id)
      end

      def remove_by_id(symbolized_sti_name, id)
        repository[symbolized_sti_name].delete(id)
      end

      def clear
        repository.clear
      end

      private

        def contain_all_columns?(record)
          (record.class.column_names - record.attribute_names).empty?
        end
    end

    # Reinitialize an Identity Map model object from +coder+.
    # +coder+ must contain the attributes necessary for initializing an empty
    # model object.
    def reinit_with(coder)
      @attributes_cache = {}
      dirty      = @changed_attributes.keys
      attributes = self.class.initialize_attributes(coder['attributes'].except(*dirty))
      @attributes.update(attributes)
      @changed_attributes.update(coder['attributes'].slice(*dirty))
      @changed_attributes.delete_if{|k,v| v.eql? @attributes[k]}

      run_callbacks :find

      self
    end

    class Middleware
      class Body #:nodoc:
        def initialize(target, original)
          @target   = target
          @original = original
        end

        def each(&block)
          @target.each(&block)
        end

        def close
          @target.close if @target.respond_to?(:close)
        ensure
          IdentityMap.enabled = @original
          IdentityMap.clear
        end
      end

      def initialize(app)
        @app = app
      end

      def call(env)
        enabled = IdentityMap.enabled
        IdentityMap.enabled = true
        status, headers, body = @app.call(env)
        [status, headers, Body.new(body, enabled)]
      end
    end
  end
end
require 'active_support/concern'

module ActiveRecord
  module Inheritance
    extend ActiveSupport::Concern

    included do
      # Determine whether to store the full constant name including namespace when using STI
      class_attribute :store_full_sti_class
      self.store_full_sti_class = true
    end

    module ClassMethods
      # True if this isn't a concrete subclass needing a STI type condition.
      def descends_from_active_record?
        if superclass.abstract_class?
          superclass.descends_from_active_record?
        else
          superclass == Base || !columns_hash.include?(inheritance_column)
        end
      end

      def finder_needs_type_condition? #:nodoc:
        # This is like this because benchmarking justifies the strange :false stuff
        :true == (@finder_needs_type_condition ||= descends_from_active_record? ? :false : :true)
      end

      def symbolized_base_class
        @symbolized_base_class ||= base_class.to_s.to_sym
      end

      def symbolized_sti_name
        @symbolized_sti_name ||= sti_name.present? ? sti_name.to_sym : symbolized_base_class
      end

      # Returns the base AR subclass that this class descends from. If A
      # extends AR::Base, A.base_class will return A. If B descends from A
      # through some arbitrarily deep hierarchy, B.base_class will return A.
      #
      # If B < A and C < B and if A is an abstract_class then both B.base_class
      # and C.base_class would return B as the answer since A is an abstract_class.
      def base_class
        class_of_active_record_descendant(self)
      end

      # Set this to true if this is an abstract class (see <tt>abstract_class?</tt>).
      attr_accessor :abstract_class

      # Returns whether this class is an abstract class or not.
      def abstract_class?
        defined?(@abstract_class) && @abstract_class == true
      end

      def sti_name
        store_full_sti_class ? name : name.demodulize
      end

      # Finder methods must instantiate through this method to work with the
      # single-table inheritance model that makes it possible to create
      # objects of different types from the same table.
      def instantiate(record)
        sti_class = find_sti_class(record[inheritance_column])
        record_id = sti_class.primary_key && record[sti_class.primary_key]

        if ActiveRecord::IdentityMap.enabled? && record_id
          instance = use_identity_map(sti_class, record_id, record)
        else
          instance = sti_class.allocate.init_with('attributes' => record)
        end

        instance
      end

      protected

      # Returns the class descending directly from ActiveRecord::Base or an
      # abstract class, if any, in the inheritance hierarchy.
      def class_of_active_record_descendant(klass)
        if klass == Base || klass.superclass == Base || klass.superclass.abstract_class?
          klass
        elsif klass.superclass.nil?
          raise ActiveRecordError, "#{name} doesn't belong in a hierarchy descending from ActiveRecord"
        else
          class_of_active_record_descendant(klass.superclass)
        end
      end

      # Returns the class type of the record using the current module as a prefix. So descendants of
      # MyApp::Business::Account would appear as MyApp::Business::AccountSubclass.
      def compute_type(type_name)
        if type_name.match(/^::/)
          # If the type is prefixed with a scope operator then we assume that
          # the type_name is an absolute reference.
          ActiveSupport::Dependencies.constantize(type_name)
        else
          # Build a list of candidates to search for
          candidates = []
          name.scan(/::|$/) { candidates.unshift "#{$`}::#{type_name}" }
          candidates << type_name

          candidates.each do |candidate|
            begin
              constant = ActiveSupport::Dependencies.constantize(candidate)
              return constant if candidate == constant.to_s
            rescue NameError => e
              # We don't want to swallow NoMethodError < NameError errors
              raise e unless e.instance_of?(NameError)
            end
          end

          raise NameError, "uninitialized constant #{candidates.first}"
        end
      end

      private

      def use_identity_map(sti_class, record_id, record)
        if (column = sti_class.columns_hash[sti_class.primary_key]) && column.number?
          record_id = record_id.to_i
        end

        if instance = IdentityMap.get(sti_class, record_id)
          instance.reinit_with('attributes' => record)
        else
          instance = sti_class.allocate.init_with('attributes' => record)
          IdentityMap.add(instance)
        end

        instance
      end

      def find_sti_class(type_name)
        if type_name.blank? || !columns_hash.include?(inheritance_column)
          self
        else
          begin
            if store_full_sti_class
              ActiveSupport::Dependencies.constantize(type_name)
            else
              compute_type(type_name)
            end
          rescue NameError
            raise SubclassNotFound,
              "The single-table inheritance mechanism failed to locate the subclass: '#{type_name}'. " +
              "This error is raised because the column '#{inheritance_column}' is reserved for storing the class in case of inheritance. " +
              "Please rename this column if you didn't intend it to be used for storing the inheritance class " +
              "or overwrite #{name}.inheritance_column to use another column for that information."
          end
        end
      end

      def type_condition(table = arel_table)
        sti_column = table[inheritance_column.to_sym]
        sti_names  = ([self] + descendants).map { |model| model.sti_name }

        sti_column.in(sti_names)
      end
    end

    private

    # Sets the attribute used for single table inheritance to this class name if this is not the
    # ActiveRecord::Base descendant.
    # Considering the hierarchy Reply < Message < ActiveRecord::Base, this makes it possible to
    # do Reply.new without having to set <tt>Reply[Reply.inheritance_column] = "Reply"</tt> yourself.
    # No such attribute would be set for objects of the Message class in that example.
    def ensure_proper_type
      klass = self.class
      if klass.finder_needs_type_condition?
        write_attribute(klass.inheritance_column, klass.sti_name)
      end
    end
  end
end
module ActiveRecord
  module Integration
    # Returns a String, which Action Pack uses for constructing an URL to this
    # object. The default implementation returns this record's id as a String,
    # or nil if this record's unsaved.
    #
    # For example, suppose that you have a User model, and that you have a
    # <tt>resources :users</tt> route. Normally, +user_path+ will
    # construct a path with the user object's 'id' in it:
    #
    #   user = User.find_by_name('Phusion')
    #   user_path(user)  # => "/users/1"
    #
    # You can override +to_param+ in your model to make +user_path+ construct
    # a path using the user's name instead of the user's id:
    #
    #   class User < ActiveRecord::Base
    #     def to_param  # overridden
    #       name
    #     end
    #   end
    #
    #   user = User.find_by_name('Phusion')
    #   user_path(user)  # => "/users/Phusion"
    def to_param
      # We can't use alias_method here, because method 'id' optimizes itself on the fly.
      id && id.to_s # Be sure to stringify the id for routes
    end

    # Returns a cache key that can be used to identify this record.
    #
    # ==== Examples
    #
    #   Product.new.cache_key     # => "products/new"
    #   Product.find(5).cache_key # => "products/5" (updated_at not available)
    #   Person.find(5).cache_key  # => "people/5-20071224150000" (updated_at available)
    def cache_key
      case
      when new_record?
        "#{self.class.model_name.cache_key}/new"
      when timestamp = self[:updated_at]
        timestamp = timestamp.utc.to_s(:number)
        "#{self.class.model_name.cache_key}/#{id}-#{timestamp}"
      else
        "#{self.class.model_name.cache_key}/#{id}"
      end
    end
  end
end
module ActiveRecord
  module Locking
    # == What is Optimistic Locking
    #
    # Optimistic locking allows multiple users to access the same record for edits, and assumes a minimum of
    # conflicts with the data. It does this by checking whether another process has made changes to a record since
    # it was opened, an <tt>ActiveRecord::StaleObjectError</tt> exception is thrown if that has occurred
    # and the update is ignored.
    #
    # Check out <tt>ActiveRecord::Locking::Pessimistic</tt> for an alternative.
    #
    # == Usage
    #
    # Active Records support optimistic locking if the field +lock_version+ is present. Each update to the
    # record increments the +lock_version+ column and the locking facilities ensure that records instantiated twice
    # will let the last one saved raise a +StaleObjectError+ if the first was also updated. Example:
    #
    #   p1 = Person.find(1)
    #   p2 = Person.find(1)
    #
    #   p1.first_name = "Michael"
    #   p1.save
    #
    #   p2.first_name = "should fail"
    #   p2.save # Raises a ActiveRecord::StaleObjectError
    #
    # Optimistic locking will also check for stale data when objects are destroyed. Example:
    #
    #   p1 = Person.find(1)
    #   p2 = Person.find(1)
    #
    #   p1.first_name = "Michael"
    #   p1.save
    #
    #   p2.destroy # Raises a ActiveRecord::StaleObjectError
    #
    # You're then responsible for dealing with the conflict by rescuing the exception and either rolling back, merging,
    # or otherwise apply the business logic needed to resolve the conflict.
    #
    # This locking mechanism will function inside a single Ruby process. To make it work across all
    # web requests, the recommended approach is to add +lock_version+ as a hidden field to your form.
    #
    # You must ensure that your database schema defaults the +lock_version+ column to 0.
    #
    # This behavior can be turned off by setting <tt>ActiveRecord::Base.lock_optimistically = false</tt>.
    # To override the name of the +lock_version+ column, invoke the <tt>set_locking_column</tt> method.
    # This method uses the same syntax as <tt>set_table_name</tt>
    module Optimistic
      extend ActiveSupport::Concern

      included do
        cattr_accessor :lock_optimistically, :instance_writer => false
        self.lock_optimistically = true
      end

      def locking_enabled? #:nodoc:
        self.class.locking_enabled?
      end

      private
        def increment_lock
          lock_col = self.class.locking_column
          previous_lock_value = send(lock_col).to_i
          send(lock_col + '=', previous_lock_value + 1)
        end

        def update(attribute_names = @attributes.keys) #:nodoc:
          return super unless locking_enabled?
          return 0 if attribute_names.empty?

          lock_col = self.class.locking_column
          previous_lock_value = send(lock_col).to_i
          increment_lock

          attribute_names += [lock_col]
          attribute_names.uniq!

          begin
            relation = self.class.unscoped

            stmt = relation.where(
              relation.table[self.class.primary_key].eq(id).and(
                relation.table[lock_col].eq(quote_value(previous_lock_value))
              )
            ).arel.compile_update(arel_attributes_values(false, false, attribute_names))

            affected_rows = connection.update stmt

            unless affected_rows == 1
              raise ActiveRecord::StaleObjectError.new(self, "update")
            end

            affected_rows

          # If something went wrong, revert the version.
          rescue Exception
            send(lock_col + '=', previous_lock_value)
            raise
          end
        end

        def destroy #:nodoc:
          return super unless locking_enabled?

          if persisted?
            table = self.class.arel_table
            lock_col = self.class.locking_column
            predicate = table[self.class.primary_key].eq(id).
              and(table[lock_col].eq(send(lock_col).to_i))

            affected_rows = self.class.unscoped.where(predicate).delete_all

            unless affected_rows == 1
              raise ActiveRecord::StaleObjectError.new(self, "destroy")
            end
          end

          @destroyed = true
          freeze
        end

      module ClassMethods
        DEFAULT_LOCKING_COLUMN = 'lock_version'

        # Returns true if the +lock_optimistically+ flag is set to true
        # (which it is, by default) and the table includes the
        # +locking_column+ column (defaults to +lock_version+).
        def locking_enabled?
          lock_optimistically && columns_hash[locking_column]
        end

        def locking_column=(value)
          @original_locking_column = @locking_column if defined?(@locking_column)
          @locking_column          = value.to_s
        end

        # Set the column to use for optimistic locking. Defaults to +lock_version+.
        def set_locking_column(value = nil, &block)
          deprecated_property_setter :locking_column, value, block
        end

        # The version column used for optimistic locking. Defaults to +lock_version+.
        def locking_column
          reset_locking_column unless defined?(@locking_column)
          @locking_column
        end

        def original_locking_column #:nodoc:
          deprecated_original_property_getter :locking_column
        end

        # Quote the column name used for optimistic locking.
        def quoted_locking_column
          connection.quote_column_name(locking_column)
        end

        # Reset the column used for optimistic locking back to the +lock_version+ default.
        def reset_locking_column
          self.locking_column = DEFAULT_LOCKING_COLUMN
        end

        # Make sure the lock version column gets updated when counters are
        # updated.
        def update_counters(id, counters)
          counters = counters.merge(locking_column => 1) if locking_enabled?
          super
        end

        # If the locking column has no default value set,
        # start the lock version at zero. Note we can't use
        # <tt>locking_enabled?</tt> at this point as
        # <tt>@attributes</tt> may not have been initialized yet.
        def initialize_attributes(attributes, options = {}) #:nodoc:
          if attributes.key?(locking_column) && lock_optimistically
            attributes[locking_column] ||= 0
          end

          attributes
        end
      end
    end
  end
end
module ActiveRecord
  module Locking
    # Locking::Pessimistic provides support for row-level locking using
    # SELECT ... FOR UPDATE and other lock types.
    #
    # Pass <tt>:lock => true</tt> to <tt>ActiveRecord::Base.find</tt> to obtain an exclusive
    # lock on the selected rows:
    #   # select * from accounts where id=1 for update
    #   Account.find(1, :lock => true)
    #
    # Pass <tt>:lock => 'some locking clause'</tt> to give a database-specific locking clause
    # of your own such as 'LOCK IN SHARE MODE' or 'FOR UPDATE NOWAIT'. Example:
    #
    #   Account.transaction do
    #     # select * from accounts where name = 'shugo' limit 1 for update
    #     shugo = Account.where("name = 'shugo'").lock(true).first
    #     yuko = Account.where("name = 'yuko'").lock(true).first
    #     shugo.balance -= 100
    #     shugo.save!
    #     yuko.balance += 100
    #     yuko.save!
    #   end
    #
    # You can also use <tt>ActiveRecord::Base#lock!</tt> method to lock one record by id.
    # This may be better if you don't need to lock every row. Example:
    #
    #   Account.transaction do
    #     # select * from accounts where ...
    #     accounts = Account.where(...).all
    #     account1 = accounts.detect { |account| ... }
    #     account2 = accounts.detect { |account| ... }
    #     # select * from accounts where id=? for update
    #     account1.lock!
    #     account2.lock!
    #     account1.balance -= 100
    #     account1.save!
    #     account2.balance += 100
    #     account2.save!
    #   end
    #
    # You can start a transaction and acquire the lock in one go by calling
    # <tt>with_lock</tt> with a block. The block is called from within
    # a transaction, the object is already locked. Example:
    #
    #   account = Account.first
    #   account.with_lock do
    #     # This block is called within a transaction,
    #     # account is already locked.
    #     account.balance -= 100
    #     account.save!
    #   end
    #
    # Database-specific information on row locking:
    #   MySQL: http://dev.mysql.com/doc/refman/5.1/en/innodb-locking-reads.html
    #   PostgreSQL: http://www.postgresql.org/docs/current/interactive/sql-select.html#SQL-FOR-UPDATE-SHARE
    module Pessimistic
      # Obtain a row lock on this record. Reloads the record to obtain the requested
      # lock. Pass an SQL locking clause to append the end of the SELECT statement
      # or pass true for "FOR UPDATE" (the default, an exclusive row lock). Returns
      # the locked record.
      def lock!(lock = true)
        reload(:lock => lock) if persisted?
        self
      end

      # Wraps the passed block in a transaction, locking the object
      # before yielding. You pass can the SQL locking clause
      # as argument (see <tt>lock!</tt>).
      def with_lock(lock = true)
        transaction do
          lock!(lock)
          yield
        end
      end
    end
  end
end
module ActiveRecord
  class LogSubscriber < ActiveSupport::LogSubscriber
    def self.runtime=(value)
      Thread.current["active_record_sql_runtime"] = value
    end

    def self.runtime
      Thread.current["active_record_sql_runtime"] ||= 0
    end

    def self.reset_runtime
      rt, self.runtime = runtime, 0
      rt
    end

    def initialize
      super
      @odd_or_even = false
    end

    def sql(event)
      self.class.runtime += event.duration
      return unless logger.debug?

      payload = event.payload

      return if 'SCHEMA' == payload[:name]

      name  = '%s (%.1fms)' % [payload[:name], event.duration]
      sql   = payload[:sql].squeeze(' ')
      binds = nil

      unless (payload[:binds] || []).empty?
        binds = "  " + payload[:binds].map { |col,v|
          [col.name, v]
        }.inspect
      end

      if odd?
        name = color(name, CYAN, true)
        sql  = color(sql, nil, true)
      else
        name = color(name, MAGENTA, true)
      end

      debug "  #{name}  #{sql}#{binds}"
    end

    def identity(event)
      return unless logger.debug?

      name = color(event.payload[:name], odd? ? CYAN : MAGENTA, true)
      line = odd? ? color(event.payload[:line], nil, true) : event.payload[:line]

      debug "  #{name}  #{line}"
    end

    def odd?
      @odd_or_even = !@odd_or_even
    end

    def logger
      ActiveRecord::Base.logger
    end
  end
end

ActiveRecord::LogSubscriber.attach_to :active_record
module ActiveRecord
  class Migration
    # <tt>ActiveRecord::Migration::CommandRecorder</tt> records commands done during
    # a migration and knows how to reverse those commands. The CommandRecorder
    # knows how to invert the following commands:
    #
    # * add_column
    # * add_index
    # * add_timestamps
    # * create_table
    # * remove_timestamps
    # * rename_column
    # * rename_index
    # * rename_table
    class CommandRecorder
      attr_accessor :commands, :delegate

      def initialize(delegate = nil)
        @commands = []
        @delegate = delegate
      end

      # record +command+. +command+ should be a method name and arguments.
      # For example:
      #
      #   recorder.record(:method_name, [:arg1, :arg2])
      def record(*command)
        @commands << command
      end

      # Returns a list that represents commands that are the inverse of the
      # commands stored in +commands+. For example:
      #
      #   recorder.record(:rename_table, [:old, :new])
      #   recorder.inverse # => [:rename_table, [:new, :old]]
      #
      # This method will raise an +IrreversibleMigration+ exception if it cannot
      # invert the +commands+.
      def inverse
        @commands.reverse.map { |name, args|
          method = :"invert_#{name}"
          raise IrreversibleMigration unless respond_to?(method, true)
          send(method, args)
        }
      end

      def respond_to?(*args) # :nodoc:
        super || delegate.respond_to?(*args)
      end

      [:create_table, :change_table, :rename_table, :add_column, :remove_column, :rename_index, :rename_column, :add_index, :remove_index, :add_timestamps, :remove_timestamps, :change_column, :change_column_default].each do |method|
        class_eval <<-EOV, __FILE__, __LINE__ + 1
          def #{method}(*args)          # def create_table(*args)
            record(:"#{method}", args)  #   record(:create_table, args)
          end                           # end
        EOV
      end

      private

      def invert_create_table(args)
        [:drop_table, [args.first]]
      end

      def invert_rename_table(args)
        [:rename_table, args.reverse]
      end

      def invert_add_column(args)
        [:remove_column, args.first(2)]
      end

      def invert_rename_index(args)
        [:rename_index, [args.first] + args.last(2).reverse]
      end

      def invert_rename_column(args)
        [:rename_column, [args.first] + args.last(2).reverse]
      end

      def invert_add_index(args)
        table, columns, options = *args
        index_name = options.try(:[], :name)
        options_hash =  index_name ? {:name => index_name} : {:column => columns}
        [:remove_index, [table, options_hash]]
      end

      def invert_remove_timestamps(args)
        [:add_timestamps, args]
      end

      def invert_add_timestamps(args)
        [:remove_timestamps, args]
      end

      # Forwards any missing method call to the \target.
      def method_missing(method, *args, &block)
        @delegate.send(method, *args, &block)
      rescue NoMethodError => e
        raise e, e.message.sub(/ for #<.*$/, " via proxy for #{@delegate}")
      end

    end
  end
end
require "active_support/core_ext/module/delegation"
require "active_support/core_ext/class/attribute_accessors"
require "active_support/core_ext/array/wrap"
require 'active_support/deprecation'

module ActiveRecord
  # Exception that can be raised to stop migrations from going backwards.
  class IrreversibleMigration < ActiveRecordError
  end

  class DuplicateMigrationVersionError < ActiveRecordError#:nodoc:
    def initialize(version)
      super("Multiple migrations have the version number #{version}")
    end
  end

  class DuplicateMigrationNameError < ActiveRecordError#:nodoc:
    def initialize(name)
      super("Multiple migrations have the name #{name}")
    end
  end

  class UnknownMigrationVersionError < ActiveRecordError #:nodoc:
    def initialize(version)
      super("No migration with version number #{version}")
    end
  end

  class IllegalMigrationNameError < ActiveRecordError#:nodoc:
    def initialize(name)
      super("Illegal name for migration file: #{name}\n\t(only lower case letters, numbers, and '_' allowed)")
    end
  end

  # = Active Record Migrations
  #
  # Migrations can manage the evolution of a schema used by several physical
  # databases. It's a solution to the common problem of adding a field to make
  # a new feature work in your local database, but being unsure of how to
  # push that change to other developers and to the production server. With
  # migrations, you can describe the transformations in self-contained classes
  # that can be checked into version control systems and executed against
  # another database that might be one, two, or five versions behind.
  #
  # Example of a simple migration:
  #
  #   class AddSsl < ActiveRecord::Migration
  #     def up
  #       add_column :accounts, :ssl_enabled, :boolean, :default => 1
  #     end
  #
  #     def down
  #       remove_column :accounts, :ssl_enabled
  #     end
  #   end
  #
  # This migration will add a boolean flag to the accounts table and remove it
  # if you're backing out of the migration. It shows how all migrations have
  # two methods +up+ and +down+ that describes the transformations
  # required to implement or remove the migration. These methods can consist
  # of both the migration specific methods like add_column and remove_column,
  # but may also contain regular Ruby code for generating data needed for the
  # transformations.
  #
  # Example of a more complex migration that also needs to initialize data:
  #
  #   class AddSystemSettings < ActiveRecord::Migration
  #     def up
  #       create_table :system_settings do |t|
  #         t.string  :name
  #         t.string  :label
  #         t.text    :value
  #         t.string  :type
  #         t.integer :position
  #       end
  #
  #       SystemSetting.create  :name => "notice",
  #                             :label => "Use notice?",
  #                             :value => 1
  #     end
  #
  #     def down
  #       drop_table :system_settings
  #     end
  #   end
  #
  # This migration first adds the system_settings table, then creates the very
  # first row in it using the Active Record model that relies on the table. It
  # also uses the more advanced create_table syntax where you can specify a
  # complete table schema in one block call.
  #
  # == Available transformations
  #
  # * <tt>create_table(name, options)</tt> Creates a table called +name+ and
  #   makes the table object available to a block that can then add columns to it,
  #   following the same format as add_column. See example above. The options hash
  #   is for fragments like "DEFAULT CHARSET=UTF-8" that are appended to the create
  #   table definition.
  # * <tt>drop_table(name)</tt>: Drops the table called +name+.
  # * <tt>rename_table(old_name, new_name)</tt>: Renames the table called +old_name+
  #   to +new_name+.
  # * <tt>add_column(table_name, column_name, type, options)</tt>: Adds a new column
  #   to the table called +table_name+
  #   named +column_name+ specified to be one of the following types:
  #   <tt>:string</tt>, <tt>:text</tt>, <tt>:integer</tt>, <tt>:float</tt>,
  #   <tt>:decimal</tt>, <tt>:datetime</tt>, <tt>:timestamp</tt>, <tt>:time</tt>,
  #   <tt>:date</tt>, <tt>:binary</tt>, <tt>:boolean</tt>. A default value can be
  #   specified by passing an +options+ hash like <tt>{ :default => 11 }</tt>.
  #   Other options include <tt>:limit</tt> and <tt>:null</tt> (e.g.
  #   <tt>{ :limit => 50, :null => false }</tt>) -- see
  #   ActiveRecord::ConnectionAdapters::TableDefinition#column for details.
  # * <tt>rename_column(table_name, column_name, new_column_name)</tt>: Renames
  #   a column but keeps the type and content.
  # * <tt>change_column(table_name, column_name, type, options)</tt>:  Changes
  #   the column to a different type using the same parameters as add_column.
  # * <tt>remove_column(table_name, column_names)</tt>: Removes the column listed in
  #   +column_names+ from the table called +table_name+.
  # * <tt>add_index(table_name, column_names, options)</tt>: Adds a new index
  #   with the name of the column. Other options include
  #   <tt>:name</tt>, <tt>:unique</tt> (e.g.
  #   <tt>{ :name => "users_name_index", :unique => true }</tt>) and <tt>:order</tt>
  #   (e.g. { :order => {:name => :desc} }</tt>).
  # * <tt>remove_index(table_name, :column => column_name)</tt>: Removes the index
  #   specified by +column_name+.
  # * <tt>remove_index(table_name, :name => index_name)</tt>: Removes the index
  #   specified by +index_name+.
  #
  # == Irreversible transformations
  #
  # Some transformations are destructive in a manner that cannot be reversed.
  # Migrations of that kind should raise an <tt>ActiveRecord::IrreversibleMigration</tt>
  # exception in their +down+ method.
  #
  # == Running migrations from within Rails
  #
  # The Rails package has several tools to help create and apply migrations.
  #
  # To generate a new migration, you can use
  #   rails generate migration MyNewMigration
  #
  # where MyNewMigration is the name of your migration. The generator will
  # create an empty migration file <tt>timestamp_my_new_migration.rb</tt>
  # in the <tt>db/migrate/</tt> directory where <tt>timestamp</tt> is the
  # UTC formatted date and time that the migration was generated.
  #
  # You may then edit the <tt>up</tt> and <tt>down</tt> methods of
  # MyNewMigration.
  #
  # There is a special syntactic shortcut to generate migrations that add fields to a table.
  #
  #   rails generate migration add_fieldname_to_tablename fieldname:string
  #
  # This will generate the file <tt>timestamp_add_fieldname_to_tablename</tt>, which will look like this:
  #   class AddFieldnameToTablename < ActiveRecord::Migration
  #     def up
  #       add_column :tablenames, :fieldname, :string
  #     end
  #
  #     def down
  #       remove_column :tablenames, :fieldname
  #     end
  #   end
  #
  # To run migrations against the currently configured database, use
  # <tt>rake db:migrate</tt>. This will update the database by running all of the
  # pending migrations, creating the <tt>schema_migrations</tt> table
  # (see "About the schema_migrations table" section below) if missing. It will also
  # invoke the db:schema:dump task, which will update your db/schema.rb file
  # to match the structure of your database.
  #
  # To roll the database back to a previous migration version, use
  # <tt>rake db:migrate VERSION=X</tt> where <tt>X</tt> is the version to which
  # you wish to downgrade. If any of the migrations throw an
  # <tt>ActiveRecord::IrreversibleMigration</tt> exception, that step will fail and you'll
  # have some manual work to do.
  #
  # == Database support
  #
  # Migrations are currently supported in MySQL, PostgreSQL, SQLite,
  # SQL Server, Sybase, and Oracle (all supported databases except DB2).
  #
  # == More examples
  #
  # Not all migrations change the schema. Some just fix the data:
  #
  #   class RemoveEmptyTags < ActiveRecord::Migration
  #     def up
  #       Tag.all.each { |tag| tag.destroy if tag.pages.empty? }
  #     end
  #
  #     def down
  #       # not much we can do to restore deleted data
  #       raise ActiveRecord::IrreversibleMigration, "Can't recover the deleted tags"
  #     end
  #   end
  #
  # Others remove columns when they migrate up instead of down:
  #
  #   class RemoveUnnecessaryItemAttributes < ActiveRecord::Migration
  #     def up
  #       remove_column :items, :incomplete_items_count
  #       remove_column :items, :completed_items_count
  #     end
  #
  #     def down
  #       add_column :items, :incomplete_items_count
  #       add_column :items, :completed_items_count
  #     end
  #   end
  #
  # And sometimes you need to do something in SQL not abstracted directly by migrations:
  #
  #   class MakeJoinUnique < ActiveRecord::Migration
  #     def up
  #       execute "ALTER TABLE `pages_linked_pages` ADD UNIQUE `page_id_linked_page_id` (`page_id`,`linked_page_id`)"
  #     end
  #
  #     def down
  #       execute "ALTER TABLE `pages_linked_pages` DROP INDEX `page_id_linked_page_id`"
  #     end
  #   end
  #
  # == Using a model after changing its table
  #
  # Sometimes you'll want to add a column in a migration and populate it
  # immediately after. In that case, you'll need to make a call to
  # <tt>Base#reset_column_information</tt> in order to ensure that the model has the
  # latest column data from after the new column was added. Example:
  #
  #   class AddPeopleSalary < ActiveRecord::Migration
  #     def up
  #       add_column :people, :salary, :integer
  #       Person.reset_column_information
  #       Person.all.each do |p|
  #         p.update_attribute :salary, SalaryCalculator.compute(p)
  #       end
  #     end
  #   end
  #
  # == Controlling verbosity
  #
  # By default, migrations will describe the actions they are taking, writing
  # them to the console as they happen, along with benchmarks describing how
  # long each step took.
  #
  # You can quiet them down by setting ActiveRecord::Migration.verbose = false.
  #
  # You can also insert your own messages and benchmarks by using the +say_with_time+
  # method:
  #
  #   def up
  #     ...
  #     say_with_time "Updating salaries..." do
  #       Person.all.each do |p|
  #         p.update_attribute :salary, SalaryCalculator.compute(p)
  #       end
  #     end
  #     ...
  #   end
  #
  # The phrase "Updating salaries..." would then be printed, along with the
  # benchmark for the block when the block completes.
  #
  # == About the schema_migrations table
  #
  # Rails versions 2.0 and prior used to create a table called
  # <tt>schema_info</tt> when using migrations. This table contained the
  # version of the schema as of the last applied migration.
  #
  # Starting with Rails 2.1, the <tt>schema_info</tt> table is
  # (automatically) replaced by the <tt>schema_migrations</tt> table, which
  # contains the version numbers of all the migrations applied.
  #
  # As a result, it is now possible to add migration files that are numbered
  # lower than the current schema version: when migrating up, those
  # never-applied "interleaved" migrations will be automatically applied, and
  # when migrating down, never-applied "interleaved" migrations will be skipped.
  #
  # == Timestamped Migrations
  #
  # By default, Rails generates migrations that look like:
  #
  #    20080717013526_your_migration_name.rb
  #
  # The prefix is a generation timestamp (in UTC).
  #
  # If you'd prefer to use numeric prefixes, you can turn timestamped migrations
  # off by setting:
  #
  #    config.active_record.timestamped_migrations = false
  #
  # In application.rb.
  #
  # == Reversible Migrations
  #
  # Starting with Rails 3.1, you will be able to define reversible migrations.
  # Reversible migrations are migrations that know how to go +down+ for you.
  # You simply supply the +up+ logic, and the Migration system will figure out
  # how to execute the down commands for you.
  #
  # To define a reversible migration, define the +change+ method in your
  # migration like this:
  #
  #   class TenderloveMigration < ActiveRecord::Migration
  #     def change
  #       create_table(:horses) do |t|
  #         t.column :content, :text
  #         t.column :remind_at, :datetime
  #       end
  #     end
  #   end
  #
  # This migration will create the horses table for you on the way up, and
  # automatically figure out how to drop the table on the way down.
  #
  # Some commands like +remove_column+ cannot be reversed.  If you care to
  # define how to move up and down in these cases, you should define the +up+
  # and +down+ methods as before.
  #
  # If a command cannot be reversed, an
  # <tt>ActiveRecord::IrreversibleMigration</tt> exception will be raised when
  # the migration is moving down.
  #
  # For a list of commands that are reversible, please see
  # <tt>ActiveRecord::Migration::CommandRecorder</tt>.
  class Migration
    autoload :CommandRecorder, 'active_record/migration/command_recorder'

    class << self
      attr_accessor :delegate # :nodoc:
    end

    def self.method_missing(name, *args, &block) # :nodoc:
      (delegate || superclass.delegate).send(name, *args, &block)
    end

    def self.migrate(direction)
      new.migrate direction
    end

    cattr_accessor :verbose

    attr_accessor :name, :version

    def initialize
      @name       = self.class.name
      @version    = nil
      @connection = nil
      @reverting  = false
    end

    # instantiate the delegate object after initialize is defined
    self.verbose  = true
    self.delegate = new

    def revert
      @reverting = true
      yield
    ensure
      @reverting = false
    end

    def reverting?
      @reverting
    end

    def up
      self.class.delegate = self
      return unless self.class.respond_to?(:up)
      self.class.up
    end

    def down
      self.class.delegate = self
      return unless self.class.respond_to?(:down)
      self.class.down
    end

    # Execute this migration in the named direction
    def migrate(direction)
      return unless respond_to?(direction)

      case direction
      when :up   then announce "migrating"
      when :down then announce "reverting"
      end

      time   = nil
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        @connection = conn
        if respond_to?(:change)
          if direction == :down
            recorder = CommandRecorder.new(@connection)
            suppress_messages do
              @connection = recorder
              change
            end
            @connection = conn
            time = Benchmark.measure {
              self.revert {
                recorder.inverse.each do |cmd, args|
                  send(cmd, *args)
                end
              }
            }
          else
            time = Benchmark.measure { change }
          end
        else
          time = Benchmark.measure { send(direction) }
        end
        @connection = nil
      end

      case direction
      when :up   then announce "migrated (%.4fs)" % time.real; write
      when :down then announce "reverted (%.4fs)" % time.real; write
      end
    end

    def write(text="")
      puts(text) if verbose
    end

    def announce(message)
      text = "#{version} #{name}: #{message}"
      length = [0, 75 - text.length].max
      write "== %s %s" % [text, "=" * length]
    end

    def say(message, subitem=false)
      write "#{subitem ? "   ->" : "--"} #{message}"
    end

    def say_with_time(message)
      say(message)
      result = nil
      time = Benchmark.measure { result = yield }
      say "%.4fs" % time.real, :subitem
      say("#{result} rows", :subitem) if result.is_a?(Integer)
      result
    end

    def suppress_messages
      save, self.verbose = verbose, false
      yield
    ensure
      self.verbose = save
    end

    def connection
      @connection || ActiveRecord::Base.connection
    end

    def method_missing(method, *arguments, &block)
      arg_list = arguments.map{ |a| a.inspect } * ', '

      say_with_time "#{method}(#{arg_list})" do
        unless reverting?
          unless arguments.empty? || method == :execute
            arguments[0] = Migrator.proper_table_name(arguments.first)
            arguments[1] = Migrator.proper_table_name(arguments.second) if method == :rename_table
          end
        end
        return super unless connection.respond_to?(method)
        connection.send(method, *arguments, &block)
      end
    end

    def copy(destination, sources, options = {})
      copied = []

      FileUtils.mkdir_p(destination) unless File.exists?(destination)

      destination_migrations = ActiveRecord::Migrator.migrations(destination)
      last = destination_migrations.last
      sources.each do |scope, path|
        source_migrations = ActiveRecord::Migrator.migrations(path)

        source_migrations.each do |migration|
          source = File.read(migration.filename)
          source = "# This migration comes from #{scope} (originally #{migration.version})\n#{source}"

          if duplicate = destination_migrations.detect { |m| m.name == migration.name }
            if options[:on_skip] && duplicate.scope != scope.to_s
              options[:on_skip].call(scope, migration)
            end
            next
          end

          migration.version = next_migration_number(last ? last.version + 1 : 0).to_i
          new_path = File.join(destination, "#{migration.version}_#{migration.name.underscore}.#{scope}.rb")
          old_path, migration.filename = migration.filename, new_path
          last = migration

          File.open(migration.filename, "w") { |f| f.write source }
          copied << migration
          options[:on_copy].call(scope, migration, old_path) if options[:on_copy]
          destination_migrations << migration
        end
      end

      copied
    end

    def next_migration_number(number)
      if ActiveRecord::Base.timestamped_migrations
        [Time.now.utc.strftime("%Y%m%d%H%M%S"), "%.14d" % number].max
      else
        "%.3d" % number
      end
    end
  end

  # MigrationProxy is used to defer loading of the actual migration classes
  # until they are needed
  class MigrationProxy < Struct.new(:name, :version, :filename, :scope)

    def initialize(name, version, filename, scope)
      super
      @migration = nil
    end

    def basename
      File.basename(filename)
    end

    delegate :migrate, :announce, :write, :to => :migration

    private

      def migration
        @migration ||= load_migration
      end

      def load_migration
        require(File.expand_path(filename))
        name.constantize.new
      end

  end

  class Migrator#:nodoc:
    class << self
      attr_writer :migrations_paths
      alias :migrations_path= :migrations_paths=

      def migrate(migrations_paths, target_version = nil, &block)
        case
          when target_version.nil?
            up(migrations_paths, target_version, &block)
          when current_version == 0 && target_version == 0
            []
          when current_version > target_version
            down(migrations_paths, target_version, &block)
          else
            up(migrations_paths, target_version, &block)
        end
      end

      def rollback(migrations_paths, steps=1)
        move(:down, migrations_paths, steps)
      end

      def forward(migrations_paths, steps=1)
        move(:up, migrations_paths, steps)
      end

      def up(migrations_paths, target_version = nil, &block)
        self.new(:up, migrations_paths, target_version).migrate(&block)
      end

      def down(migrations_paths, target_version = nil, &block)
        self.new(:down, migrations_paths, target_version).migrate(&block)
      end

      def run(direction, migrations_paths, target_version)
        self.new(direction, migrations_paths, target_version).run
      end

      def schema_migrations_table_name
        Base.table_name_prefix + 'schema_migrations' + Base.table_name_suffix
      end

      def get_all_versions
        table = Arel::Table.new(schema_migrations_table_name)
        Base.connection.select_values(table.project(table['version'])).map{ |v| v.to_i }.sort
      end

      def current_version
        sm_table = schema_migrations_table_name
        if Base.connection.table_exists?(sm_table)
          get_all_versions.max || 0
        else
          0
        end
      end

      def proper_table_name(name)
        # Use the Active Record objects own table_name, or pre/suffix from ActiveRecord::Base if name is a symbol/string
        name.table_name rescue "#{ActiveRecord::Base.table_name_prefix}#{name}#{ActiveRecord::Base.table_name_suffix}"
      end

      def migrations_paths
        @migrations_paths ||= ['db/migrate']
        # just to not break things if someone uses: migration_path = some_string
        Array.wrap(@migrations_paths)
      end

      def migrations_path
        migrations_paths.first
      end

      def migrations(paths, *args)
        if args.empty?
          subdirectories = true
        else
          subdirectories = args.first
          ActiveSupport::Deprecation.warn "The `subdirectories` argument to `migrations` is deprecated"
        end

        paths = Array.wrap(paths)

        glob = subdirectories ? "**/" : ""
        files = Dir[*paths.map { |p| "#{p}/#{glob}[0-9]*_*.rb" }]

        seen = Hash.new false

        migrations = files.map do |file|
          version, name, scope = file.scan(/([0-9]+)_([_a-z0-9]*)\.?([_a-z0-9]*)?.rb/).first

          raise IllegalMigrationNameError.new(file) unless version
          version = version.to_i
          name = name.camelize

          raise DuplicateMigrationVersionError.new(version) if seen[version]
          raise DuplicateMigrationNameError.new(name) if seen[name]

          seen[version] = seen[name] = true

          MigrationProxy.new(name, version, file, scope)
        end

        migrations.sort_by(&:version)
      end

      private

      def move(direction, migrations_paths, steps)
        migrator = self.new(direction, migrations_paths)
        start_index = migrator.migrations.index(migrator.current_migration)

        if start_index
          finish = migrator.migrations[start_index + steps]
          version = finish ? finish.version : 0
          send(direction, migrations_paths, version)
        end
      end
    end

    def initialize(direction, migrations_paths, target_version = nil)
      raise StandardError.new("This database does not yet support migrations") unless Base.connection.supports_migrations?
      Base.connection.initialize_schema_migrations_table
      @direction, @migrations_paths, @target_version = direction, migrations_paths, target_version
    end

    def current_version
      migrated.last || 0
    end

    def current_migration
      migrations.detect { |m| m.version == current_version }
    end

    def run
      target = migrations.detect { |m| m.version == @target_version }
      raise UnknownMigrationVersionError.new(@target_version) if target.nil?
      unless (up? && migrated.include?(target.version.to_i)) || (down? && !migrated.include?(target.version.to_i))
        target.migrate(@direction)
        record_version_state_after_migrating(target.version)
      end
    end

    def migrate(&block)
      current = migrations.detect { |m| m.version == current_version }
      target = migrations.detect { |m| m.version == @target_version }

      if target.nil? && @target_version && @target_version > 0
        raise UnknownMigrationVersionError.new(@target_version)
      end

      start = up? ? 0 : (migrations.index(current) || 0)
      finish = migrations.index(target) || migrations.size - 1
      runnable = migrations[start..finish]

      # skip the last migration if we're headed down, but not ALL the way down
      runnable.pop if down? && target

      ran = []
      runnable.each do |migration|
        if block && !block.call(migration)
          next
        end

        Base.logger.info "Migrating to #{migration.name} (#{migration.version})" if Base.logger

        seen = migrated.include?(migration.version.to_i)

        # On our way up, we skip migrating the ones we've already migrated
        next if up? && seen

        # On our way down, we skip reverting the ones we've never migrated
        if down? && !seen
          migration.announce 'never migrated, skipping'; migration.write
          next
        end

        begin
          ddl_transaction do
            migration.migrate(@direction)
            record_version_state_after_migrating(migration.version)
          end
          ran << migration
        rescue => e
          canceled_msg = Base.connection.supports_ddl_transactions? ? "this and " : ""
          raise StandardError, "An error has occurred, #{canceled_msg}all later migrations canceled:\n\n#{e}", e.backtrace
        end
      end
      ran
    end

    def migrations
      @migrations ||= begin
        migrations = self.class.migrations(@migrations_paths)
        down? ? migrations.reverse : migrations
      end
    end

    def pending_migrations
      already_migrated = migrated
      migrations.reject { |m| already_migrated.include?(m.version.to_i) }
    end

    def migrated
      @migrated_versions ||= self.class.get_all_versions
    end

    private
      def record_version_state_after_migrating(version)
        table = Arel::Table.new(self.class.schema_migrations_table_name)

        @migrated_versions ||= []
        if down?
          @migrated_versions.delete(version)
          stmt = table.where(table["version"].eq(version.to_s)).compile_delete
          Base.connection.delete stmt
        else
          @migrated_versions.push(version).sort!
          stmt = table.compile_insert table["version"] => version.to_s
          Base.connection.insert stmt
        end
      end

      def up?
        @direction == :up
      end

      def down?
        @direction == :down
      end

      # Wrap the migration in a transaction only if supported by the adapter.
      def ddl_transaction(&block)
        if Base.connection.supports_ddl_transactions?
          Base.transaction { block.call }
        else
          block.call
        end
      end
  end
end
require 'active_support/concern'

module ActiveRecord
  module ModelSchema
    extend ActiveSupport::Concern

    included do
      ##
      # :singleton-method:
      # Accessor for the prefix type that will be prepended to every primary key column name.
      # The options are :table_name and :table_name_with_underscore. If the first is specified,
      # the Product class will look for "productid" instead of "id" as the primary column. If the
      # latter is specified, the Product class will look for "product_id" instead of "id". Remember
      # that this is a global setting for all Active Records.
      cattr_accessor :primary_key_prefix_type, :instance_writer => false
      self.primary_key_prefix_type = nil

      ##
      # :singleton-method:
      # Accessor for the name of the prefix string to prepend to every table name. So if set
      # to "basecamp_", all table names will be named like "basecamp_projects", "basecamp_people",
      # etc. This is a convenient way of creating a namespace for tables in a shared database.
      # By default, the prefix is the empty string.
      #
      # If you are organising your models within modules you can add a prefix to the models within
      # a namespace by defining a singleton method in the parent module called table_name_prefix which
      # returns your chosen prefix.
      class_attribute :table_name_prefix, :instance_writer => false
      self.table_name_prefix = ""

      ##
      # :singleton-method:
      # Works like +table_name_prefix+, but appends instead of prepends (set to "_basecamp" gives "projects_basecamp",
      # "people_basecamp"). By default, the suffix is the empty string.
      class_attribute :table_name_suffix, :instance_writer => false
      self.table_name_suffix = ""

      ##
      # :singleton-method:
      # Indicates whether table names should be the pluralized versions of the corresponding class names.
      # If true, the default table name for a Product class will be +products+. If false, it would just be +product+.
      # See table_name for the full rules on table/class naming. This is true, by default.
      class_attribute :pluralize_table_names, :instance_writer => false
      self.pluralize_table_names = true
    end

    module ClassMethods
      # Guesses the table name (in forced lower-case) based on the name of the class in the
      # inheritance hierarchy descending directly from ActiveRecord::Base. So if the hierarchy
      # looks like: Reply < Message < ActiveRecord::Base, then Message is used
      # to guess the table name even when called on Reply. The rules used to do the guess
      # are handled by the Inflector class in Active Support, which knows almost all common
      # English inflections. You can add new inflections in config/initializers/inflections.rb.
      #
      # Nested classes are given table names prefixed by the singular form of
      # the parent's table name. Enclosing modules are not considered.
      #
      # ==== Examples
      #
      #   class Invoice < ActiveRecord::Base
      #   end
      #
      #   file                  class               table_name
      #   invoice.rb            Invoice             invoices
      #
      #   class Invoice < ActiveRecord::Base
      #     class Lineitem < ActiveRecord::Base
      #     end
      #   end
      #
      #   file                  class               table_name
      #   invoice.rb            Invoice::Lineitem   invoice_lineitems
      #
      #   module Invoice
      #     class Lineitem < ActiveRecord::Base
      #     end
      #   end
      #
      #   file                  class               table_name
      #   invoice/lineitem.rb   Invoice::Lineitem   lineitems
      #
      # Additionally, the class-level +table_name_prefix+ is prepended and the
      # +table_name_suffix+ is appended. So if you have "myapp_" as a prefix,
      # the table name guess for an Invoice class becomes "myapp_invoices".
      # Invoice::Lineitem becomes "myapp_invoice_lineitems".
      #
      # You can also set your own table name explicitly:
      #
      #   class Mouse < ActiveRecord::Base
      #     self.table_name = "mice"
      #   end
      #
      # Alternatively, you can override the table_name method to define your
      # own computation. (Possibly using <tt>super</tt> to manipulate the default
      # table name.) Example:
      #
      #   class Post < ActiveRecord::Base
      #     def self.table_name
      #       "special_" + super
      #     end
      #   end
      #   Post.table_name # => "special_posts"
      def table_name
        reset_table_name unless defined?(@table_name)
        @table_name
      end

      def original_table_name #:nodoc:
        deprecated_original_property_getter :table_name
      end

      # Sets the table name explicitly. Example:
      #
      #   class Project < ActiveRecord::Base
      #     self.table_name = "project"
      #   end
      #
      # You can also just define your own <tt>self.table_name</tt> method; see
      # the documentation for ActiveRecord::Base#table_name.
      def table_name=(value)
        @original_table_name = @table_name if defined?(@table_name)
        @table_name          = value && value.to_s
        @quoted_table_name   = nil
        @arel_table          = nil
        @relation            = Relation.new(self, arel_table)
      end

      def set_table_name(value = nil, &block) #:nodoc:
        deprecated_property_setter :table_name, value, block
        @quoted_table_name = nil
        @arel_table        = nil
        @relation          = Relation.new(self, arel_table)
      end

      # Returns a quoted version of the table name, used to construct SQL statements.
      def quoted_table_name
        @quoted_table_name ||= connection.quote_table_name(table_name)
      end

      # Computes the table name, (re)sets it internally, and returns it.
      def reset_table_name #:nodoc:
        if abstract_class?
          self.table_name = if superclass == Base || superclass.abstract_class?
                              nil
                            else
                              superclass.table_name
                            end
        elsif superclass.abstract_class?
          self.table_name = superclass.table_name || compute_table_name
        else
          self.table_name = compute_table_name
        end
      end

      def full_table_name_prefix #:nodoc:
        (parents.detect{ |p| p.respond_to?(:table_name_prefix) } || self).table_name_prefix
      end

      # The name of the column containing the object's class when Single Table Inheritance is used
      def inheritance_column
        if self == Base
          'type'
        else
          (@inheritance_column ||= nil) || superclass.inheritance_column
        end
      end

      def original_inheritance_column #:nodoc:
        deprecated_original_property_getter :inheritance_column
      end

      # Sets the value of inheritance_column
      def inheritance_column=(value)
        @original_inheritance_column = inheritance_column
        @inheritance_column          = value.to_s
      end

      def set_inheritance_column(value = nil, &block) #:nodoc:
        deprecated_property_setter :inheritance_column, value, block
      end

      def sequence_name
        if base_class == self
          @sequence_name ||= reset_sequence_name
        else
          (@sequence_name ||= nil) || base_class.sequence_name
        end
      end

      def original_sequence_name #:nodoc:
        deprecated_original_property_getter :sequence_name
      end

      def reset_sequence_name #:nodoc:
        self.sequence_name = connection.default_sequence_name(table_name, primary_key)
      end

      # Sets the name of the sequence to use when generating ids to the given
      # value, or (if the value is nil or false) to the value returned by the
      # given block. This is required for Oracle and is useful for any
      # database which relies on sequences for primary key generation.
      #
      # If a sequence name is not explicitly set when using Oracle or Firebird,
      # it will default to the commonly used pattern of: #{table_name}_seq
      #
      # If a sequence name is not explicitly set when using PostgreSQL, it
      # will discover the sequence corresponding to your primary key for you.
      #
      #   class Project < ActiveRecord::Base
      #     self.sequence_name = "projectseq"   # default would have been "project_seq"
      #   end
      def sequence_name=(value)
        @original_sequence_name = @sequence_name if defined?(@sequence_name)
        @sequence_name          = value.to_s
      end

      def set_sequence_name(value = nil, &block) #:nodoc:
        deprecated_property_setter :sequence_name, value, block
      end

      # Indicates whether the table associated with this class exists
      def table_exists?
        connection.schema_cache.table_exists?(table_name)
      end

      # Returns an array of column objects for the table associated with this class.
      def columns
        @columns ||= connection.schema_cache.columns[table_name].map do |col|
          col = col.dup
          col.primary = (col.name == primary_key)
          col
        end
      end

      # Returns a hash of column objects for the table associated with this class.
      def columns_hash
        @columns_hash ||= Hash[columns.map { |c| [c.name, c] }]
      end

      # Returns a hash where the keys are column names and the values are
      # default values when instantiating the AR object for this table.
      def column_defaults
        @column_defaults ||= Hash[columns.map { |c| [c.name, c.default] }]
      end

      # Returns an array of column names as strings.
      def column_names
        @column_names ||= columns.map { |column| column.name }
      end

      # Returns an array of column objects where the primary id, all columns ending in "_id" or "_count",
      # and columns used for single table inheritance have been removed.
      def content_columns
        @content_columns ||= columns.reject { |c| c.primary || c.name =~ /(_id|_count)$/ || c.name == inheritance_column }
      end

      # Returns a hash of all the methods added to query each of the columns in the table with the name of the method as the key
      # and true as the value. This makes it possible to do O(1) lookups in respond_to? to check if a given method for attribute
      # is available.
      def column_methods_hash #:nodoc:
        @dynamic_methods_hash ||= column_names.inject(Hash.new(false)) do |methods, attr|
          attr_name = attr.to_s
          methods[attr.to_sym]       = attr_name
          methods["#{attr}=".to_sym] = attr_name
          methods["#{attr}?".to_sym] = attr_name
          methods["#{attr}_before_type_cast".to_sym] = attr_name
          methods
        end
      end

      # Resets all the cached information about columns, which will cause them
      # to be reloaded on the next request.
      #
      # The most common usage pattern for this method is probably in a migration,
      # when just after creating a table you want to populate it with some default
      # values, eg:
      #
      #  class CreateJobLevels < ActiveRecord::Migration
      #    def up
      #      create_table :job_levels do |t|
      #        t.integer :id
      #        t.string :name
      #
      #        t.timestamps
      #      end
      #
      #      JobLevel.reset_column_information
      #      %w{assistant executive manager director}.each do |type|
      #        JobLevel.create(:name => type)
      #      end
      #    end
      #
      #    def down
      #      drop_table :job_levels
      #    end
      #  end
      def reset_column_information
        connection.clear_cache!
        undefine_attribute_methods
        connection.schema_cache.clear_table_cache!(table_name) if table_exists?

        @column_names = @content_columns = @column_defaults = @columns = @columns_hash = nil
        @dynamic_methods_hash = @inheritance_column = nil
        @arel_engine = @relation = nil
      end

      def clear_cache! # :nodoc:
        connection.schema_cache.clear!
      end

      private

      # Guesses the table name, but does not decorate it with prefix and suffix information.
      def undecorated_table_name(class_name = base_class.name)
        table_name = class_name.to_s.demodulize.underscore
        table_name = table_name.pluralize if pluralize_table_names
        table_name
      end

      # Computes and returns a table name according to default conventions.
      def compute_table_name
        base = base_class
        if self == base
          # Nested classes are prefixed with singular parent table name.
          if parent < ActiveRecord::Base && !parent.abstract_class?
            contained = parent.table_name
            contained = contained.singularize if parent.pluralize_table_names
            contained += '_'
          end
          "#{full_table_name_prefix}#{contained}#{undecorated_table_name(name)}#{table_name_suffix}"
        else
          # STI subclasses always use their superclass' table.
          base.table_name
        end
      end

      def deprecated_property_setter(property, value, block)
        if block
          ActiveSupport::Deprecation.warn(
            "Calling set_#{property} is deprecated. If you need to lazily evaluate " \
            "the #{property}, define your own `self.#{property}` class method. You can use `super` " \
            "to get the default #{property} where you would have called `original_#{property}`."
          )

          define_attr_method property, value, false, &block
        else
          ActiveSupport::Deprecation.warn(
            "Calling set_#{property} is deprecated. Please use `self.#{property} = 'the_name'` instead."
          )

          define_attr_method property, value, false
        end
      end

      def deprecated_original_property_getter(property)
        ActiveSupport::Deprecation.warn("original_#{property} is deprecated. Define self.#{property} and call super instead.")

        if !instance_variable_defined?("@original_#{property}") && respond_to?("reset_#{property}")
          send("reset_#{property}")
        else
          instance_variable_get("@original_#{property}")
        end
      end
    end
  end
end
require 'active_support/core_ext/hash/except'
require 'active_support/core_ext/object/try'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/class/attribute'

module ActiveRecord
  module NestedAttributes #:nodoc:
    class TooManyRecords < ActiveRecordError
    end

    extend ActiveSupport::Concern

    included do
      class_attribute :nested_attributes_options, :instance_writer => false
      self.nested_attributes_options = {}
    end

    # = Active Record Nested Attributes
    #
    # Nested attributes allow you to save attributes on associated records
    # through the parent. By default nested attribute updating is turned off,
    # you can enable it using the accepts_nested_attributes_for class method.
    # When you enable nested attributes an attribute writer is defined on
    # the model.
    #
    # The attribute writer is named after the association, which means that
    # in the following example, two new methods are added to your model:
    #
    # <tt>author_attributes=(attributes)</tt> and
    # <tt>pages_attributes=(attributes)</tt>.
    #
    #   class Book < ActiveRecord::Base
    #     has_one :author
    #     has_many :pages
    #
    #     accepts_nested_attributes_for :author, :pages
    #   end
    #
    # Note that the <tt>:autosave</tt> option is automatically enabled on every
    # association that accepts_nested_attributes_for is used for.
    #
    # === One-to-one
    #
    # Consider a Member model that has one Avatar:
    #
    #   class Member < ActiveRecord::Base
    #     has_one :avatar
    #     accepts_nested_attributes_for :avatar
    #   end
    #
    # Enabling nested attributes on a one-to-one association allows you to
    # create the member and avatar in one go:
    #
    #   params = { :member => { :name => 'Jack', :avatar_attributes => { :icon => 'smiling' } } }
    #   member = Member.create(params[:member])
    #   member.avatar.id # => 2
    #   member.avatar.icon # => 'smiling'
    #
    # It also allows you to update the avatar through the member:
    #
    #   params = { :member => { :avatar_attributes => { :id => '2', :icon => 'sad' } } }
    #   member.update_attributes params[:member]
    #   member.avatar.icon # => 'sad'
    #
    # By default you will only be able to set and update attributes on the
    # associated model. If you want to destroy the associated model through the
    # attributes hash, you have to enable it first using the
    # <tt>:allow_destroy</tt> option.
    #
    #   class Member < ActiveRecord::Base
    #     has_one :avatar
    #     accepts_nested_attributes_for :avatar, :allow_destroy => true
    #   end
    #
    # Now, when you add the <tt>_destroy</tt> key to the attributes hash, with a
    # value that evaluates to +true+, you will destroy the associated model:
    #
    #   member.avatar_attributes = { :id => '2', :_destroy => '1' }
    #   member.avatar.marked_for_destruction? # => true
    #   member.save
    #   member.reload.avatar # => nil
    #
    # Note that the model will _not_ be destroyed until the parent is saved.
    #
    # === One-to-many
    #
    # Consider a member that has a number of posts:
    #
    #   class Member < ActiveRecord::Base
    #     has_many :posts
    #     accepts_nested_attributes_for :posts
    #   end
    #
    # You can now set or update attributes on an associated post model through
    # the attribute hash.
    #
    # For each hash that does _not_ have an <tt>id</tt> key a new record will
    # be instantiated, unless the hash also contains a <tt>_destroy</tt> key
    # that evaluates to +true+.
    #
    #   params = { :member => {
    #     :name => 'joe', :posts_attributes => [
    #       { :title => 'Kari, the awesome Ruby documentation browser!' },
    #       { :title => 'The egalitarian assumption of the modern citizen' },
    #       { :title => '', :_destroy => '1' } # this will be ignored
    #     ]
    #   }}
    #
    #   member = Member.create(params['member'])
    #   member.posts.length # => 2
    #   member.posts.first.title # => 'Kari, the awesome Ruby documentation browser!'
    #   member.posts.second.title # => 'The egalitarian assumption of the modern citizen'
    #
    # You may also set a :reject_if proc to silently ignore any new record
    # hashes if they fail to pass your criteria. For example, the previous
    # example could be rewritten as:
    #
    #    class Member < ActiveRecord::Base
    #      has_many :posts
    #      accepts_nested_attributes_for :posts, :reject_if => proc { |attributes| attributes['title'].blank? }
    #    end
    #
    #   params = { :member => {
    #     :name => 'joe', :posts_attributes => [
    #       { :title => 'Kari, the awesome Ruby documentation browser!' },
    #       { :title => 'The egalitarian assumption of the modern citizen' },
    #       { :title => '' } # this will be ignored because of the :reject_if proc
    #     ]
    #   }}
    #
    #   member = Member.create(params['member'])
    #   member.posts.length # => 2
    #   member.posts.first.title # => 'Kari, the awesome Ruby documentation browser!'
    #   member.posts.second.title # => 'The egalitarian assumption of the modern citizen'
    #
    # Alternatively, :reject_if also accepts a symbol for using methods:
    #
    #    class Member < ActiveRecord::Base
    #      has_many :posts
    #      accepts_nested_attributes_for :posts, :reject_if => :new_record?
    #    end
    #
    #    class Member < ActiveRecord::Base
    #      has_many :posts
    #      accepts_nested_attributes_for :posts, :reject_if => :reject_posts
    #
    #      def reject_posts(attributed)
    #        attributed['title'].blank?
    #      end
    #    end
    #
    # If the hash contains an <tt>id</tt> key that matches an already
    # associated record, the matching record will be modified:
    #
    #   member.attributes = {
    #     :name => 'Joe',
    #     :posts_attributes => [
    #       { :id => 1, :title => '[UPDATED] An, as of yet, undisclosed awesome Ruby documentation browser!' },
    #       { :id => 2, :title => '[UPDATED] other post' }
    #     ]
    #   }
    #
    #   member.posts.first.title # => '[UPDATED] An, as of yet, undisclosed awesome Ruby documentation browser!'
    #   member.posts.second.title # => '[UPDATED] other post'
    #
    # By default the associated records are protected from being destroyed. If
    # you want to destroy any of the associated records through the attributes
    # hash, you have to enable it first using the <tt>:allow_destroy</tt>
    # option. This will allow you to also use the <tt>_destroy</tt> key to
    # destroy existing records:
    #
    #   class Member < ActiveRecord::Base
    #     has_many :posts
    #     accepts_nested_attributes_for :posts, :allow_destroy => true
    #   end
    #
    #   params = { :member => {
    #     :posts_attributes => [{ :id => '2', :_destroy => '1' }]
    #   }}
    #
    #   member.attributes = params['member']
    #   member.posts.detect { |p| p.id == 2 }.marked_for_destruction? # => true
    #   member.posts.length # => 2
    #   member.save
    #   member.reload.posts.length # => 1
    #
    # === Saving
    #
    # All changes to models, including the destruction of those marked for
    # destruction, are saved and destroyed automatically and atomically when
    # the parent model is saved. This happens inside the transaction initiated
    # by the parents save method. See ActiveRecord::AutosaveAssociation.
    #
    # === Using with attr_accessible
    #
    # The use of <tt>attr_accessible</tt> can interfere with nested attributes
    # if you're not careful. For example, if the <tt>Member</tt> model above
    # was using <tt>attr_accessible</tt> like this:
    #
    #   attr_accessible :name
    #
    # You would need to modify it to look like this:
    #
    #   attr_accessible :name, :posts_attributes
    #
    # === Validating the presence of a parent model
    #
    # If you want to validate that a child record is associated with a parent
    # record, you can use <tt>validates_presence_of</tt> and
    # <tt>inverse_of</tt> as this example illustrates:
    #
    #   class Member < ActiveRecord::Base
    #     has_many :posts, :inverse_of => :member
    #     accepts_nested_attributes_for :posts
    #   end
    #
    #   class Post < ActiveRecord::Base
    #     belongs_to :member, :inverse_of => :posts
    #     validates_presence_of :member
    #   end
    module ClassMethods
      REJECT_ALL_BLANK_PROC = proc { |attributes| attributes.all? { |key, value| key == '_destroy' || value.blank? } }

      # Defines an attributes writer for the specified association(s). If you
      # are using <tt>attr_protected</tt> or <tt>attr_accessible</tt>, then you
      # will need to add the attribute writer to the allowed list.
      #
      # Supported options:
      # [:allow_destroy]
      #   If true, destroys any members from the attributes hash with a
      #   <tt>_destroy</tt> key and a value that evaluates to +true+
      #   (eg. 1, '1', true, or 'true'). This option is off by default.
      # [:reject_if]
      #   Allows you to specify a Proc or a Symbol pointing to a method
      #   that checks whether a record should be built for a certain attribute
      #   hash. The hash is passed to the supplied Proc or the method
      #   and it should return either +true+ or +false+. When no :reject_if
      #   is specified, a record will be built for all attribute hashes that
      #   do not have a <tt>_destroy</tt> value that evaluates to true.
      #   Passing <tt>:all_blank</tt> instead of a Proc will create a proc
      #   that will reject a record where all the attributes are blank excluding
      #   any value for _destroy.
      # [:limit]
      #   Allows you to specify the maximum number of the associated records that
      #   can be processed with the nested attributes. If the size of the
      #   nested attributes array exceeds the specified limit, NestedAttributes::TooManyRecords
      #   exception is raised. If omitted, any number associations can be processed.
      #   Note that the :limit option is only applicable to one-to-many associations.
      # [:update_only]
      #   Allows you to specify that an existing record may only be updated.
      #   A new record may only be created when there is no existing record.
      #   This option only works for one-to-one associations and is ignored for
      #   collection associations. This option is off by default.
      #
      # Examples:
      #   # creates avatar_attributes=
      #   accepts_nested_attributes_for :avatar, :reject_if => proc { |attributes| attributes['name'].blank? }
      #   # creates avatar_attributes=
      #   accepts_nested_attributes_for :avatar, :reject_if => :all_blank
      #   # creates avatar_attributes= and posts_attributes=
      #   accepts_nested_attributes_for :avatar, :posts, :allow_destroy => true
      def accepts_nested_attributes_for(*attr_names)
        options = { :allow_destroy => false, :update_only => false }
        options.update(attr_names.extract_options!)
        options.assert_valid_keys(:allow_destroy, :reject_if, :limit, :update_only)
        options[:reject_if] = REJECT_ALL_BLANK_PROC if options[:reject_if] == :all_blank

        attr_names.each do |association_name|
          if reflection = reflect_on_association(association_name)
            reflection.options[:autosave] = true
            add_autosave_association_callbacks(reflection)

            nested_attributes_options = self.nested_attributes_options.dup
            nested_attributes_options[association_name.to_sym] = options
            self.nested_attributes_options = nested_attributes_options

            type = (reflection.collection? ? :collection : :one_to_one)

            # def pirate_attributes=(attributes)
            #   assign_nested_attributes_for_one_to_one_association(:pirate, attributes, mass_assignment_options)
            # end
            class_eval <<-eoruby, __FILE__, __LINE__ + 1
              if method_defined?(:#{association_name}_attributes=)
                remove_method(:#{association_name}_attributes=)
              end
              def #{association_name}_attributes=(attributes)
                assign_nested_attributes_for_#{type}_association(:#{association_name}, attributes, mass_assignment_options)
              end
            eoruby
          else
            raise ArgumentError, "No association found for name `#{association_name}'. Has it been defined yet?"
          end
        end
      end
    end

    # Returns ActiveRecord::AutosaveAssociation::marked_for_destruction? It's
    # used in conjunction with fields_for to build a form element for the
    # destruction of this association.
    #
    # See ActionView::Helpers::FormHelper::fields_for for more info.
    def _destroy
      marked_for_destruction?
    end

    private

    # Attribute hash keys that should not be assigned as normal attributes.
    # These hash keys are nested attributes implementation details.
    UNASSIGNABLE_KEYS = %w( id _destroy )

    # Assigns the given attributes to the association.
    #
    # If update_only is false and the given attributes include an <tt>:id</tt>
    # that matches the existing record's id, then the existing record will be
    # modified. If update_only is true, a new record is only created when no
    # object exists. Otherwise a new record will be built.
    #
    # If the given attributes include a matching <tt>:id</tt> attribute, or
    # update_only is true, and a <tt>:_destroy</tt> key set to a truthy value,
    # then the existing record will be marked for destruction.
    def assign_nested_attributes_for_one_to_one_association(association_name, attributes, assignment_opts = {})
      options = self.nested_attributes_options[association_name]
      attributes = attributes.with_indifferent_access

      if (options[:update_only] || !attributes['id'].blank?) && (record = send(association_name)) &&
          (options[:update_only] || record.id.to_s == attributes['id'].to_s)
        assign_to_or_mark_for_destruction(record, attributes, options[:allow_destroy], assignment_opts) unless call_reject_if(association_name, attributes)

      elsif attributes['id'].present? && !assignment_opts[:without_protection]
        raise_nested_attributes_record_not_found(association_name, attributes['id'])

      elsif !reject_new_record?(association_name, attributes)
        method = "build_#{association_name}"
        if respond_to?(method)
          send(method, attributes.except(*unassignable_keys(assignment_opts)), assignment_opts)
        else
          raise ArgumentError, "Cannot build association #{association_name}. Are you trying to build a polymorphic one-to-one association?"
        end
      end
    end

    # Assigns the given attributes to the collection association.
    #
    # Hashes with an <tt>:id</tt> value matching an existing associated record
    # will update that record. Hashes without an <tt>:id</tt> value will build
    # a new record for the association. Hashes with a matching <tt>:id</tt>
    # value and a <tt>:_destroy</tt> key set to a truthy value will mark the
    # matched record for destruction.
    #
    # For example:
    #
    #   assign_nested_attributes_for_collection_association(:people, {
    #     '1' => { :id => '1', :name => 'Peter' },
    #     '2' => { :name => 'John' },
    #     '3' => { :id => '2', :_destroy => true }
    #   })
    #
    # Will update the name of the Person with ID 1, build a new associated
    # person with the name `John', and mark the associated Person with ID 2
    # for destruction.
    #
    # Also accepts an Array of attribute hashes:
    #
    #   assign_nested_attributes_for_collection_association(:people, [
    #     { :id => '1', :name => 'Peter' },
    #     { :name => 'John' },
    #     { :id => '2', :_destroy => true }
    #   ])
    def assign_nested_attributes_for_collection_association(association_name, attributes_collection, assignment_opts = {})
      options = self.nested_attributes_options[association_name]

      unless attributes_collection.is_a?(Hash) || attributes_collection.is_a?(Array)
        raise ArgumentError, "Hash or Array expected, got #{attributes_collection.class.name} (#{attributes_collection.inspect})"
      end

      if options[:limit] && attributes_collection.size > options[:limit]
        raise TooManyRecords, "Maximum #{options[:limit]} records are allowed. Got #{attributes_collection.size} records instead."
      end

      if attributes_collection.is_a? Hash
        keys = attributes_collection.keys
        attributes_collection = if keys.include?('id') || keys.include?(:id)
          Array.wrap(attributes_collection)
        else
          attributes_collection.values
        end
      end

      association = association(association_name)

      existing_records = if association.loaded?
        association.target
      else
        attribute_ids = attributes_collection.map {|a| a['id'] || a[:id] }.compact
        attribute_ids.empty? ? [] : association.scoped.where(association.klass.primary_key => attribute_ids)
      end

      attributes_collection.each do |attributes|
        attributes = attributes.with_indifferent_access

        if attributes['id'].blank?
          unless reject_new_record?(association_name, attributes)
            association.build(attributes.except(*unassignable_keys(assignment_opts)), assignment_opts)
          end
        elsif existing_record = existing_records.detect { |record| record.id.to_s == attributes['id'].to_s }
          unless association.loaded? || call_reject_if(association_name, attributes)
            # Make sure we are operating on the actual object which is in the association's
            # proxy_target array (either by finding it, or adding it if not found)
            target_record = association.target.detect { |record| record == existing_record }

            if target_record
              existing_record = target_record
            else
              association.add_to_target(existing_record)
            end

          end

          if !call_reject_if(association_name, attributes)
            assign_to_or_mark_for_destruction(existing_record, attributes, options[:allow_destroy], assignment_opts)
          end
        elsif assignment_opts[:without_protection]
          association.build(attributes.except(*unassignable_keys(assignment_opts)), assignment_opts)
        else
          raise_nested_attributes_record_not_found(association_name, attributes['id'])
        end
      end
    end

    # Updates a record with the +attributes+ or marks it for destruction if
    # +allow_destroy+ is +true+ and has_destroy_flag? returns +true+.
    def assign_to_or_mark_for_destruction(record, attributes, allow_destroy, assignment_opts)
      record.assign_attributes(attributes.except(*unassignable_keys(assignment_opts)), assignment_opts)
      record.mark_for_destruction if has_destroy_flag?(attributes) && allow_destroy
    end

    # Determines if a hash contains a truthy _destroy key.
    def has_destroy_flag?(hash)
      ConnectionAdapters::Column.value_to_boolean(hash['_destroy'])
    end

    # Determines if a new record should be build by checking for
    # has_destroy_flag? or if a <tt>:reject_if</tt> proc exists for this
    # association and evaluates to +true+.
    def reject_new_record?(association_name, attributes)
      has_destroy_flag?(attributes) || call_reject_if(association_name, attributes)
    end

    def call_reject_if(association_name, attributes)
      return false if has_destroy_flag?(attributes)
      case callback = self.nested_attributes_options[association_name][:reject_if]
      when Symbol
        method(callback).arity == 0 ? send(callback) : send(callback, attributes)
      when Proc
        callback.call(attributes)
      end
    end

    def raise_nested_attributes_record_not_found(association_name, record_id)
      raise RecordNotFound, "Couldn't find #{self.class.reflect_on_association(association_name).klass.name} with ID=#{record_id} for #{self.class.name} with ID=#{id}"
    end

    def unassignable_keys(assignment_opts)
      assignment_opts[:without_protection] ? UNASSIGNABLE_KEYS - %w[id] : UNASSIGNABLE_KEYS
    end
  end
end
require 'active_support/core_ext/class/attribute'

module ActiveRecord
  # = Active Record Observer
  #
  # Observer classes respond to life cycle callbacks to implement trigger-like
  # behavior outside the original class. This is a great way to reduce the
  # clutter that normally comes when the model class is burdened with
  # functionality that doesn't pertain to the core responsibility of the
  # class. Example:
  #
  #   class CommentObserver < ActiveRecord::Observer
  #     def after_save(comment)
  #       Notifications.comment("admin@do.com", "New comment was posted", comment).deliver
  #     end
  #   end
  #
  # This Observer sends an email when a Comment#save is finished.
  #
  #   class ContactObserver < ActiveRecord::Observer
  #     def after_create(contact)
  #       contact.logger.info('New contact added!')
  #     end
  #
  #     def after_destroy(contact)
  #       contact.logger.warn("Contact with an id of #{contact.id} was destroyed!")
  #     end
  #   end
  #
  # This Observer uses logger to log when specific callbacks are triggered.
  #
  # == Observing a class that can't be inferred
  #
  # Observers will by default be mapped to the class with which they share a name. So CommentObserver will
  # be tied to observing Comment, ProductManagerObserver to ProductManager, and so on. If you want to name your observer
  # differently than the class you're interested in observing, you can use the Observer.observe class method which takes
  # either the concrete class (Product) or a symbol for that class (:product):
  #
  #   class AuditObserver < ActiveRecord::Observer
  #     observe :account
  #
  #     def after_update(account)
  #       AuditTrail.new(account, "UPDATED")
  #     end
  #   end
  #
  # If the audit observer needs to watch more than one kind of object, this can be specified with multiple arguments:
  #
  #   class AuditObserver < ActiveRecord::Observer
  #     observe :account, :balance
  #
  #     def after_update(record)
  #       AuditTrail.new(record, "UPDATED")
  #     end
  #   end
  #
  # The AuditObserver will now act on both updates to Account and Balance by treating them both as records.
  #
  # == Available callback methods
  #
  # The observer can implement callback methods for each of the methods described in the Callbacks module.
  #
  # == Storing Observers in Rails
  #
  # If you're using Active Record within Rails, observer classes are usually stored in app/models with the
  # naming convention of app/models/audit_observer.rb.
  #
  # == Configuration
  #
  # In order to activate an observer, list it in the <tt>config.active_record.observers</tt> configuration
  # setting in your <tt>config/application.rb</tt> file.
  #
  #   config.active_record.observers = :comment_observer, :signup_observer
  #
  # Observers will not be invoked unless you define these in your application configuration.
  #
  # == Loading
  #
  # Observers register themselves in the model class they observe, since it is the class that
  # notifies them of events when they occur. As a side-effect, when an observer is loaded its
  # corresponding model class is loaded.
  #
  # Up to (and including) Rails 2.0.2 observers were instantiated between plugins and
  # application initializers. Now observers are loaded after application initializers,
  # so observed models can make use of extensions.
  #
  # If by any chance you are using observed models in the initialization you can still
  # load their observers by calling <tt>ModelObserver.instance</tt> before. Observers are
  # singletons and that call instantiates and registers them.
  #
  class Observer < ActiveModel::Observer

    protected

      def observed_classes
        klasses = super
        klasses + klasses.map { |klass| klass.descendants }.flatten
      end

      def add_observer!(klass)
        super
        define_callbacks klass
      end

      def define_callbacks(klass)
        observer = self
        observer_name = observer.class.name.underscore.gsub('/', '__')

        ActiveRecord::Callbacks::CALLBACKS.each do |callback|
          next unless respond_to?(callback)
          callback_meth = :"_notify_#{observer_name}_for_#{callback}"
          unless klass.respond_to?(callback_meth)
            klass.send(:define_method, callback_meth) do |&block|
              observer.update(callback, self, &block)
            end
            klass.send(callback, callback_meth)
          end
        end
      end
  end
end
require 'active_support/concern'

module ActiveRecord
  # = Active Record Persistence
  module Persistence
    extend ActiveSupport::Concern

    module ClassMethods
      # Creates an object (or multiple objects) and saves it to the database, if validations pass.
      # The resulting object is returned whether the object was saved successfully to the database or not.
      #
      # The +attributes+ parameter can be either be a Hash or an Array of Hashes. These Hashes describe the
      # attributes on the objects that are to be created.
      #
      # +create+ respects mass-assignment security and accepts either +:as+ or +:without_protection+ options
      # in the +options+ parameter.
      #
      # ==== Examples
      #   # Create a single new object
      #   User.create(:first_name => 'Jamie')
      #
      #   # Create a single new object using the :admin mass-assignment security role
      #   User.create({ :first_name => 'Jamie', :is_admin => true }, :as => :admin)
      #
      #   # Create a single new object bypassing mass-assignment security
      #   User.create({ :first_name => 'Jamie', :is_admin => true }, :without_protection => true)
      #
      #   # Create an Array of new objects
      #   User.create([{ :first_name => 'Jamie' }, { :first_name => 'Jeremy' }])
      #
      #   # Create a single object and pass it into a block to set other attributes.
      #   User.create(:first_name => 'Jamie') do |u|
      #     u.is_admin = false
      #   end
      #
      #   # Creating an Array of new objects using a block, where the block is executed for each object:
      #   User.create([{ :first_name => 'Jamie' }, { :first_name => 'Jeremy' }]) do |u|
      #     u.is_admin = false
      #   end
      def create(attributes = nil, options = {}, &block)
        if attributes.is_a?(Array)
          attributes.collect { |attr| create(attr, options, &block) }
        else
          object = new(attributes, options, &block)
          object.save
          object
        end
      end
    end

    # Returns true if this object hasn't been saved yet -- that is, a record
    # for the object doesn't exist in the data store yet; otherwise, returns false.
    def new_record?
      @new_record
    end

    # Returns true if this object has been destroyed, otherwise returns false.
    def destroyed?
      @destroyed
    end

    # Returns if the record is persisted, i.e. it's not a new record and it was
    # not destroyed.
    def persisted?
      !(new_record? || destroyed?)
    end

    # Saves the model.
    #
    # If the model is new a record gets created in the database, otherwise
    # the existing record gets updated.
    #
    # By default, save always run validations. If any of them fail the action
    # is cancelled and +save+ returns +false+. However, if you supply
    # :validate => false, validations are bypassed altogether. See
    # ActiveRecord::Validations for more information.
    #
    # There's a series of callbacks associated with +save+. If any of the
    # <tt>before_*</tt> callbacks return +false+ the action is cancelled and
    # +save+ returns +false+. See ActiveRecord::Callbacks for further
    # details.
    def save(*)
      begin
        create_or_update
      rescue ActiveRecord::RecordInvalid
        false
      end
    end

    # Saves the model.
    #
    # If the model is new a record gets created in the database, otherwise
    # the existing record gets updated.
    #
    # With <tt>save!</tt> validations always run. If any of them fail
    # ActiveRecord::RecordInvalid gets raised. See ActiveRecord::Validations
    # for more information.
    #
    # There's a series of callbacks associated with <tt>save!</tt>. If any of
    # the <tt>before_*</tt> callbacks return +false+ the action is cancelled
    # and <tt>save!</tt> raises ActiveRecord::RecordNotSaved. See
    # ActiveRecord::Callbacks for further details.
    def save!(*)
      create_or_update || raise(RecordNotSaved)
    end

    # Deletes the record in the database and freezes this instance to
    # reflect that no changes should be made (since they can't be
    # persisted). Returns the frozen instance.
    #
    # The row is simply removed with an SQL +DELETE+ statement on the
    # record's primary key, and no callbacks are executed.
    #
    # To enforce the object's +before_destroy+ and +after_destroy+
    # callbacks, Observer methods, or any <tt>:dependent</tt> association
    # options, use <tt>#destroy</tt>.
    def delete
      if persisted?
        self.class.delete(id)
        IdentityMap.remove(self) if IdentityMap.enabled?
      end
      @destroyed = true
      freeze
    end

    # Deletes the record in the database and freezes this instance to reflect
    # that no changes should be made (since they can't be persisted).
    def destroy
      destroy_associations

      if persisted?
        IdentityMap.remove(self) if IdentityMap.enabled?
        pk         = self.class.primary_key
        column     = self.class.columns_hash[pk]
        substitute = connection.substitute_at(column, 0)

        relation = self.class.unscoped.where(
          self.class.arel_table[pk].eq(substitute))

        relation.bind_values = [[column, id]]
        relation.delete_all
      end

      @destroyed = true
      freeze
    end

    # Returns an instance of the specified +klass+ with the attributes of the
    # current record. This is mostly useful in relation to single-table
    # inheritance structures where you want a subclass to appear as the
    # superclass. This can be used along with record identification in
    # Action Pack to allow, say, <tt>Client < Company</tt> to do something
    # like render <tt>:partial => @client.becomes(Company)</tt> to render that
    # instance using the companies/company partial instead of clients/client.
    #
    # Note: The new instance will share a link to the same attributes as the original class.
    # So any change to the attributes in either instance will affect the other.
    def becomes(klass)
      became = klass.new
      became.instance_variable_set("@attributes", @attributes)
      became.instance_variable_set("@attributes_cache", @attributes_cache)
      became.instance_variable_set("@new_record", new_record?)
      became.instance_variable_set("@destroyed", destroyed?)
      became.instance_variable_set("@errors", errors)
      became.send("#{klass.inheritance_column}=", klass.name) unless self.class.descends_from_active_record?
      became
    end

    # Updates a single attribute and saves the record.
    # This is especially useful for boolean flags on existing records. Also note that
    #
    # * Validation is skipped.
    # * Callbacks are invoked.
    # * updated_at/updated_on column is updated if that column is available.
    # * Updates all the attributes that are dirty in this object.
    #
    def update_attribute(name, value)
      name = name.to_s
      raise ActiveRecordError, "#{name} is marked as readonly" if self.class.readonly_attributes.include?(name)
      send("#{name}=", value)
      save(:validate => false)
    end

    # Updates a single attribute of an object, without calling save.
    #
    # * Validation is skipped.
    # * Callbacks are skipped.
    # * updated_at/updated_on column is not updated if that column is available.
    #
    # Raises an +ActiveRecordError+ when called on new objects, or when the +name+
    # attribute is marked as readonly.
    def update_column(name, value)
      name = name.to_s
      raise ActiveRecordError, "#{name} is marked as readonly" if self.class.readonly_attributes.include?(name)
      raise ActiveRecordError, "can not update on a new record object" unless persisted?

      updated_count = self.class.update_all({ name => value }, self.class.primary_key => id)

      raw_write_attribute(name, value)

      updated_count == 1
    end

    # Updates the attributes of the model from the passed-in hash and saves the
    # record, all wrapped in a transaction. If the object is invalid, the saving
    # will fail and false will be returned.
    #
    # When updating model attributes, mass-assignment security protection is respected.
    # If no +:as+ option is supplied then the +:default+ role will be used.
    # If you want to bypass the protection given by +attr_protected+ and
    # +attr_accessible+ then you can do so using the +:without_protection+ option.
    def update_attributes(attributes, options = {})
      # The following transaction covers any possible database side-effects of the
      # attributes assignment. For example, setting the IDs of a child collection.
      with_transaction_returning_status do
        self.assign_attributes(attributes, options)
        save
      end
    end

    # Updates its receiver just like +update_attributes+ but calls <tt>save!</tt> instead
    # of +save+, so an exception is raised if the record is invalid.
    def update_attributes!(attributes, options = {})
      # The following transaction covers any possible database side-effects of the
      # attributes assignment. For example, setting the IDs of a child collection.
      with_transaction_returning_status do
        self.assign_attributes(attributes, options)
        save!
      end
    end

    # Initializes +attribute+ to zero if +nil+ and adds the value passed as +by+ (default is 1).
    # The increment is performed directly on the underlying attribute, no setter is invoked.
    # Only makes sense for number-based attributes. Returns +self+.
    def increment(attribute, by = 1)
      self[attribute] ||= 0
      self[attribute] += by
      self
    end

    # Wrapper around +increment+ that saves the record. This method differs from
    # its non-bang version in that it passes through the attribute setter.
    # Saving is not subjected to validation checks. Returns +true+ if the
    # record could be saved.
    def increment!(attribute, by = 1)
      increment(attribute, by).update_attribute(attribute, self[attribute])
    end

    # Initializes +attribute+ to zero if +nil+ and subtracts the value passed as +by+ (default is 1).
    # The decrement is performed directly on the underlying attribute, no setter is invoked.
    # Only makes sense for number-based attributes. Returns +self+.
    def decrement(attribute, by = 1)
      self[attribute] ||= 0
      self[attribute] -= by
      self
    end

    # Wrapper around +decrement+ that saves the record. This method differs from
    # its non-bang version in that it passes through the attribute setter.
    # Saving is not subjected to validation checks. Returns +true+ if the
    # record could be saved.
    def decrement!(attribute, by = 1)
      decrement(attribute, by).update_attribute(attribute, self[attribute])
    end

    # Assigns to +attribute+ the boolean opposite of <tt>attribute?</tt>. So
    # if the predicate returns +true+ the attribute will become +false+. This
    # method toggles directly the underlying value without calling any setter.
    # Returns +self+.
    def toggle(attribute)
      self[attribute] = !send("#{attribute}?")
      self
    end

    # Wrapper around +toggle+ that saves the record. This method differs from
    # its non-bang version in that it passes through the attribute setter.
    # Saving is not subjected to validation checks. Returns +true+ if the
    # record could be saved.
    def toggle!(attribute)
      toggle(attribute).update_attribute(attribute, self[attribute])
    end

    # Reloads the attributes of this object from the database.
    # The optional options argument is passed to find when reloading so you
    # may do e.g. record.reload(:lock => true) to reload the same record with
    # an exclusive row lock.
    def reload(options = nil)
      clear_aggregation_cache
      clear_association_cache

      IdentityMap.without do
        fresh_object = self.class.unscoped { self.class.find(self.id, options) }
        @attributes.update(fresh_object.instance_variable_get('@attributes'))
      end

      @attributes_cache = {}
      self
    end

    # Saves the record with the updated_at/on attributes set to the current time.
    # Please note that no validation is performed and no callbacks are executed.
    # If an attribute name is passed, that attribute is updated along with
    # updated_at/on attributes.
    #
    #   product.touch               # updates updated_at/on
    #   product.touch(:designed_at) # updates the designed_at attribute and updated_at/on
    #
    # If used along with +belongs_to+ then +touch+ will invoke +touch+ method on associated object.
    #
    #   class Brake < ActiveRecord::Base
    #     belongs_to :car, :touch => true
    #   end
    #
    #   class Car < ActiveRecord::Base
    #     belongs_to :corporation, :touch => true
    #   end
    #
    #   # triggers @brake.car.touch and @brake.car.corporation.touch
    #   @brake.touch
    def touch(name = nil)
      attributes = timestamp_attributes_for_update_in_model
      attributes << name if name

      unless attributes.empty?
        current_time = current_time_from_proper_timezone
        changes = {}

        attributes.each do |column|
          changes[column.to_s] = write_attribute(column.to_s, current_time)
        end

        changes[self.class.locking_column] = increment_lock if locking_enabled?

        @changed_attributes.except!(*changes.keys)
        primary_key = self.class.primary_key
        self.class.unscoped.update_all(changes, { primary_key => self[primary_key] }) == 1
      end
    end

  private

    # A hook to be overridden by association modules.
    def destroy_associations
    end

    def create_or_update
      raise ReadOnlyRecord if readonly?
      result = new_record? ? create : update
      result != false
    end

    # Updates the associated record with values matching those of the instance attributes.
    # Returns the number of affected rows.
    def update(attribute_names = @attributes.keys)
      attributes_with_values = arel_attributes_values(false, false, attribute_names)
      return 0 if attributes_with_values.empty?
      klass = self.class
      stmt = klass.unscoped.where(klass.arel_table[klass.primary_key].eq(id)).arel.compile_update(attributes_with_values)
      klass.connection.update stmt
    end

    # Creates a record with values matching those of the instance attributes
    # and returns its id.
    def create
      attributes_values = arel_attributes_values(!id.nil?)

      new_id = self.class.unscoped.insert attributes_values

      self.id ||= new_id if self.class.primary_key

      IdentityMap.add(self) if IdentityMap.enabled?
      @new_record = false
      id
    end
  end
end
require 'active_support/core_ext/object/blank'

module ActiveRecord
  # = Active Record Query Cache
  class QueryCache
    module ClassMethods
      # Enable the query cache within the block if Active Record is configured.
      def cache(&block)
        if ActiveRecord::Base.configurations.blank?
          yield
        else
          connection.cache(&block)
        end
      end

      # Disable the query cache within the block if Active Record is configured.
      def uncached(&block)
        if ActiveRecord::Base.configurations.blank?
          yield
        else
          connection.uncached(&block)
        end
      end
    end

    def initialize(app)
      @app = app
    end

    class BodyProxy # :nodoc:
      def initialize(original_cache_value, target, connection_id)
        @original_cache_value = original_cache_value
        @target               = target
        @connection_id        = connection_id
      end

      def method_missing(method_sym, *arguments, &block)
        @target.send(method_sym, *arguments, &block)
      end

      def respond_to?(method_sym, include_private = false)
        super || @target.respond_to?(method_sym)
      end

      def each(&block)
        @target.each(&block)
      end

      def close
        @target.close if @target.respond_to?(:close)
      ensure
        ActiveRecord::Base.connection_id = @connection_id
        ActiveRecord::Base.connection.clear_query_cache
        unless @original_cache_value
          ActiveRecord::Base.connection.disable_query_cache!
        end
      end
    end

    def call(env)
      old = ActiveRecord::Base.connection.query_cache_enabled
      ActiveRecord::Base.connection.enable_query_cache!

      status, headers, body = @app.call(env)
      [status, headers, BodyProxy.new(old, body, ActiveRecord::Base.connection_id)]
    rescue Exception => e
      ActiveRecord::Base.connection.clear_query_cache
      unless old
        ActiveRecord::Base.connection.disable_query_cache!
      end
      raise e
    end
  end
end
require 'active_support/core_ext/module/delegation'

module ActiveRecord
  module Querying
    delegate :find, :first, :first!, :last, :last!, :all, :exists?, :any?, :many?, :to => :scoped
    delegate :first_or_create, :first_or_create!, :first_or_initialize, :to => :scoped
    delegate :destroy, :destroy_all, :delete, :delete_all, :update, :update_all, :to => :scoped
    delegate :find_each, :find_in_batches, :to => :scoped
    delegate :select, :group, :order, :except, :reorder, :limit, :offset, :joins,
             :where, :preload, :eager_load, :includes, :from, :lock, :readonly,
             :having, :create_with, :uniq, :to => :scoped
    delegate :count, :average, :minimum, :maximum, :sum, :calculate, :pluck, :to => :scoped

    # Executes a custom SQL query against your database and returns all the results. The results will
    # be returned as an array with columns requested encapsulated as attributes of the model you call
    # this method from. If you call <tt>Product.find_by_sql</tt> then the results will be returned in
    # a Product object with the attributes you specified in the SQL query.
    #
    # If you call a complicated SQL query which spans multiple tables the columns specified by the
    # SELECT will be attributes of the model, whether or not they are columns of the corresponding
    # table.
    #
    # The +sql+ parameter is a full SQL query as a string. It will be called as is, there will be
    # no database agnostic conversions performed. This should be a last resort because using, for example,
    # MySQL specific terms will lock you to using that particular database engine or require you to
    # change your call if you switch engines.
    #
    # ==== Examples
    #   # A simple SQL query spanning multiple tables
    #   Post.find_by_sql "SELECT p.title, c.author FROM posts p, comments c WHERE p.id = c.post_id"
    #   > [#<Post:0x36bff9c @attributes={"title"=>"Ruby Meetup", "first_name"=>"Quentin"}>, ...]
    #
    #   # You can use the same string replacement techniques as you can with ActiveRecord#find
    #   Post.find_by_sql ["SELECT title FROM posts WHERE author = ? AND created > ?", author_id, start_date]
    #   > [#<Post:0x36bff9c @attributes={"title"=>"The Cheap Man Buys Twice"}>, ...]
    def find_by_sql(sql, binds = [])
      logging_query_plan do
        connection.select_all(sanitize_sql(sql), "#{name} Load", binds).collect! { |record| instantiate(record) }
      end
    end

    # Returns the result of an SQL statement that should only include a COUNT(*) in the SELECT part.
    # The use of this method should be restricted to complicated SQL queries that can't be executed
    # using the ActiveRecord::Calculations class methods. Look into those before using this.
    #
    # ==== Parameters
    #
    # * +sql+ - An SQL statement which should return a count query from the database, see the example below.
    #
    # ==== Examples
    #
    #   Product.count_by_sql "SELECT COUNT(*) FROM sales s, customers c WHERE s.customer_id = c.id"
    def count_by_sql(sql)
      sql = sanitize_conditions(sql)
      connection.select_value(sql, "#{name} Count").to_i
    end
  end
end
require "active_record"
require "rails"
require "active_model/railtie"

# For now, action_controller must always be present with
# rails, so let's make sure that it gets required before
# here. This is needed for correctly setting up the middleware.
# In the future, this might become an optional require.
require "action_controller/railtie"

module ActiveRecord
  # = Active Record Railtie
  class Railtie < Rails::Railtie
    config.active_record = ActiveSupport::OrderedOptions.new

    config.app_generators.orm :active_record, :migration => true,
                                              :timestamps => true

    config.app_middleware.insert_after "::ActionDispatch::Callbacks",
      "ActiveRecord::QueryCache"

    config.app_middleware.insert_after "::ActionDispatch::Callbacks",
      "ActiveRecord::ConnectionAdapters::ConnectionManagement"

    config.action_dispatch.rescue_responses.merge!(
      'ActiveRecord::RecordNotFound'   => :not_found,
      'ActiveRecord::StaleObjectError' => :conflict,
      'ActiveRecord::RecordInvalid'    => :unprocessable_entity,
      'ActiveRecord::RecordNotSaved'   => :unprocessable_entity
    )

    rake_tasks do
      load "active_record/railties/databases.rake"
    end

    # When loading console, force ActiveRecord::Base to be loaded
    # to avoid cross references when loading a constant for the
    # first time. Also, make it output to STDERR.
    console do |app|
      require "active_record/railties/console_sandbox" if app.sandbox?
      ActiveRecord::Base.logger = Logger.new(STDERR)
    end

    initializer "active_record.initialize_timezone" do
      ActiveSupport.on_load(:active_record) do
        self.time_zone_aware_attributes = true
        self.default_timezone = :utc
      end
    end

    initializer "active_record.logger" do
      ActiveSupport.on_load(:active_record) { self.logger ||= ::Rails.logger }
    end

    initializer "active_record.identity_map" do |app|
      config.app_middleware.insert_after "::ActionDispatch::Callbacks",
        "ActiveRecord::IdentityMap::Middleware" if config.active_record.delete(:identity_map)
    end

    initializer "active_record.set_configs" do |app|
      ActiveSupport.on_load(:active_record) do
        if app.config.active_record.delete(:whitelist_attributes)
          attr_accessible(nil)
        end
        app.config.active_record.each do |k,v|
          send "#{k}=", v
        end
      end
    end

    # This sets the database configuration from Configuration#database_configuration
    # and then establishes the connection.
    initializer "active_record.initialize_database" do |app|
      ActiveSupport.on_load(:active_record) do
        db_connection_type = "DATABASE_URL"
        unless ENV['DATABASE_URL']
          db_connection_type  = "database.yml"
          self.configurations = app.config.database_configuration
        end
        Rails.logger.info "Connecting to database specified by #{db_connection_type}"

        establish_connection
      end
    end

    # Expose database runtime to controller for logging.
    initializer "active_record.log_runtime" do |app|
      require "active_record/railties/controller_runtime"
      ActiveSupport.on_load(:action_controller) do
        include ActiveRecord::Railties::ControllerRuntime
      end
    end

    initializer "active_record.set_reloader_hooks" do |app|
      hook = lambda do
        ActiveRecord::Base.clear_reloadable_connections!
        ActiveRecord::Base.clear_cache!
      end

      if app.config.reload_classes_only_on_change
        ActiveSupport.on_load(:active_record) do
          ActionDispatch::Reloader.to_prepare(&hook)
        end
      else
        ActiveSupport.on_load(:active_record) do
          ActionDispatch::Reloader.to_cleanup(&hook)
        end
      end
    end

    initializer "active_record.add_watchable_files" do |app|
      config.watchable_files.concat ["#{app.root}/db/schema.rb", "#{app.root}/db/structure.sql"]
    end

    config.after_initialize do
      ActiveSupport.on_load(:active_record) do
        instantiate_observers

        ActionDispatch::Reloader.to_prepare do
          ActiveRecord::Base.instantiate_observers
        end
      end
    end
  end
end
ActiveRecord::Base.connection.increment_open_transactions
ActiveRecord::Base.connection.begin_db_transaction
at_exit do
  ActiveRecord::Base.connection.rollback_db_transaction
  ActiveRecord::Base.connection.decrement_open_transactions
end
require 'active_support/core_ext/module/attr_internal'
require 'active_record/log_subscriber'

module ActiveRecord
  module Railties
    module ControllerRuntime #:nodoc:
      extend ActiveSupport::Concern

    protected

      attr_internal :db_runtime

      def process_action(action, *args)
        # We also need to reset the runtime before each action
        # because of queries in middleware or in cases we are streaming
        # and it won't be cleaned up by the method below.
        ActiveRecord::LogSubscriber.reset_runtime
        super
      end

      def cleanup_view_runtime
        if ActiveRecord::Base.connected?
          db_rt_before_render = ActiveRecord::LogSubscriber.reset_runtime
          runtime = super
          db_rt_after_render = ActiveRecord::LogSubscriber.reset_runtime
          self.db_runtime = db_rt_before_render + db_rt_after_render
          runtime - db_rt_after_render
        else
          super
        end
      end

      def append_info_to_payload(payload)
        super
        if ActiveRecord::Base.connected?
          payload[:db_runtime] = (db_runtime || 0) + ActiveRecord::LogSubscriber.reset_runtime
        end
      end

      module ClassMethods
        def log_process_action(payload)
          messages, db_runtime = super, payload[:db_runtime]
          messages << ("ActiveRecord: %.1fms" % db_runtime.to_f) if db_runtime
          messages
        end
      end
    end
  end
end
#FIXME Remove if ArJdbcMysql will give.
module ArJdbcMySQL #:nodoc:
  class Error < StandardError
    attr_accessor :error_number, :sql_state

    def initialize msg
      super
      @error_number = nil
      @sql_state    = nil
    end

    # Mysql gem compatibility
    alias_method :errno, :error_number
    alias_method :error, :message
  end
end
require 'active_support/concern'
require 'active_support/core_ext/class/attribute'

module ActiveRecord
  module ReadonlyAttributes
    extend ActiveSupport::Concern

    included do
      class_attribute :_attr_readonly, :instance_writer => false
      self._attr_readonly = []
    end

    module ClassMethods
      # Attributes listed as readonly will be used to create a new record but update operations will
      # ignore these fields.
      def attr_readonly(*attributes)
        self._attr_readonly = Set.new(attributes.map { |a| a.to_s }) + (self._attr_readonly || [])
      end

      # Returns an array of all the attributes that have been specified as readonly.
      def readonly_attributes
        self._attr_readonly
      end
    end
  end
end
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/object/inclusion'

module ActiveRecord
  # = Active Record Reflection
  module Reflection # :nodoc:
    extend ActiveSupport::Concern

    included do
      class_attribute :reflections
      self.reflections = {}
    end

    # Reflection enables to interrogate Active Record classes and objects
    # about their associations and aggregations. This information can,
    # for example, be used in a form builder that takes an Active Record object
    # and creates input fields for all of the attributes depending on their type
    # and displays the associations to other objects.
    #
    # MacroReflection class has info for AggregateReflection and AssociationReflection
    # classes.
    module ClassMethods
      def create_reflection(macro, name, options, active_record)
        case macro
          when :has_many, :belongs_to, :has_one, :has_and_belongs_to_many
            klass = options[:through] ? ThroughReflection : AssociationReflection
            reflection = klass.new(macro, name, options, active_record)
          when :composed_of
            reflection = AggregateReflection.new(macro, name, options, active_record)
        end

        self.reflections = self.reflections.merge(name => reflection)
        reflection
      end

      # Returns an array of AggregateReflection objects for all the aggregations in the class.
      def reflect_on_all_aggregations
        reflections.values.grep(AggregateReflection)
      end

      # Returns the AggregateReflection object for the named +aggregation+ (use the symbol).
      #
      #   Account.reflect_on_aggregation(:balance) # => the balance AggregateReflection
      #
      def reflect_on_aggregation(aggregation)
        reflections[aggregation].is_a?(AggregateReflection) ? reflections[aggregation] : nil
      end

      # Returns an array of AssociationReflection objects for all the
      # associations in the class. If you only want to reflect on a certain
      # association type, pass in the symbol (<tt>:has_many</tt>, <tt>:has_one</tt>,
      # <tt>:belongs_to</tt>) as the first parameter.
      #
      # Example:
      #
      #   Account.reflect_on_all_associations             # returns an array of all associations
      #   Account.reflect_on_all_associations(:has_many)  # returns an array of all has_many associations
      #
      def reflect_on_all_associations(macro = nil)
        association_reflections = reflections.values.grep(AssociationReflection)
        macro ? association_reflections.select { |reflection| reflection.macro == macro } : association_reflections
      end

      # Returns the AssociationReflection object for the +association+ (use the symbol).
      #
      #   Account.reflect_on_association(:owner)             # returns the owner AssociationReflection
      #   Invoice.reflect_on_association(:line_items).macro  # returns :has_many
      #
      def reflect_on_association(association)
        reflections[association].is_a?(AssociationReflection) ? reflections[association] : nil
      end

      # Returns an array of AssociationReflection objects for all associations which have <tt>:autosave</tt> enabled.
      def reflect_on_all_autosave_associations
        reflections.values.select { |reflection| reflection.options[:autosave] }
      end
    end


    # Abstract base class for AggregateReflection and AssociationReflection. Objects of
    # AggregateReflection and AssociationReflection are returned by the Reflection::ClassMethods.
    class MacroReflection
      # Returns the name of the macro.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns <tt>:balance</tt>
      # <tt>has_many :clients</tt> returns <tt>:clients</tt>
      attr_reader :name

      # Returns the macro type.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns <tt>:composed_of</tt>
      # <tt>has_many :clients</tt> returns <tt>:has_many</tt>
      attr_reader :macro

      # Returns the hash of options used for the macro.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns <tt>{ :class_name => "Money" }</tt>
      # <tt>has_many :clients</tt> returns +{}+
      attr_reader :options

      attr_reader :active_record

      attr_reader :plural_name # :nodoc:

      def initialize(macro, name, options, active_record)
        @macro         = macro
        @name          = name
        @options       = options
        @active_record = active_record
        @plural_name   = active_record.pluralize_table_names ?
                            name.to_s.pluralize : name.to_s
      end

      # Returns the class for the macro.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns the Money class
      # <tt>has_many :clients</tt> returns the Client class
      def klass
        @klass ||= class_name.constantize
      end

      # Returns the class name for the macro.
      #
      # <tt>composed_of :balance, :class_name => 'Money'</tt> returns <tt>'Money'</tt>
      # <tt>has_many :clients</tt> returns <tt>'Client'</tt>
      def class_name
        @class_name ||= (options[:class_name] || derive_class_name).to_s
      end

      # Returns +true+ if +self+ and +other_aggregation+ have the same +name+ attribute, +active_record+ attribute,
      # and +other_aggregation+ has an options hash assigned to it.
      def ==(other_aggregation)
        super ||
          other_aggregation.kind_of?(self.class) &&
          name == other_aggregation.name &&
          other_aggregation.options &&
          active_record == other_aggregation.active_record
      end

      def sanitized_conditions #:nodoc:
        @sanitized_conditions ||= klass.send(:sanitize_sql, options[:conditions]) if options[:conditions]
      end

      private
        def derive_class_name
          name.to_s.camelize
        end
    end


    # Holds all the meta-data about an aggregation as it was specified in the
    # Active Record class.
    class AggregateReflection < MacroReflection #:nodoc:
    end

    # Holds all the meta-data about an association as it was specified in the
    # Active Record class.
    class AssociationReflection < MacroReflection #:nodoc:
      # Returns the target association's class.
      #
      #   class Author < ActiveRecord::Base
      #     has_many :books
      #   end
      #
      #   Author.reflect_on_association(:books).klass
      #   # => Book
      #
      # <b>Note:</b> Do not call +klass.new+ or +klass.create+ to instantiate
      # a new association object. Use +build_association+ or +create_association+
      # instead. This allows plugins to hook into association object creation.
      def klass
        @klass ||= active_record.send(:compute_type, class_name)
      end

      def initialize(macro, name, options, active_record)
        super
        @collection = macro.in?([:has_many, :has_and_belongs_to_many])
      end

      # Returns a new, unsaved instance of the associated class. +options+ will
      # be passed to the class's constructor.
      def build_association(*options, &block)
        klass.new(*options, &block)
      end

      def table_name
        @table_name ||= klass.table_name
      end

      def quoted_table_name
        @quoted_table_name ||= klass.quoted_table_name
      end

      def foreign_key
        @foreign_key ||= options[:foreign_key] || derive_foreign_key
      end

      def foreign_type
        @foreign_type ||= options[:foreign_type] || "#{name}_type"
      end

      def type
        @type ||= options[:as] && "#{options[:as]}_type"
      end

      def primary_key_column
        @primary_key_column ||= klass.columns.find { |c| c.name == klass.primary_key }
      end

      def association_foreign_key
        @association_foreign_key ||= options[:association_foreign_key] || class_name.foreign_key
      end

      # klass option is necessary to support loading polymorphic associations
      def association_primary_key(klass = nil)
        options[:primary_key] || primary_key(klass || self.klass)
      end

      def active_record_primary_key
        @active_record_primary_key ||= options[:primary_key] || primary_key(active_record)
      end

      def counter_cache_column
        if options[:counter_cache] == true
          "#{active_record.name.demodulize.underscore.pluralize}_count"
        elsif options[:counter_cache]
          options[:counter_cache].to_s
        end
      end

      def columns(tbl_name, log_msg)
        @columns ||= klass.connection.columns(tbl_name, log_msg)
      end

      def reset_column_information
        @columns = nil
      end

      def check_validity!
        check_validity_of_inverse!
      end

      def check_validity_of_inverse!
        unless options[:polymorphic]
          if has_inverse? && inverse_of.nil?
            raise InverseOfAssociationNotFoundError.new(self)
          end
        end
      end

      def through_reflection
        nil
      end

      def source_reflection
        nil
      end

      # A chain of reflections from this one back to the owner. For more see the explanation in
      # ThroughReflection.
      def chain
        [self]
      end

      def nested?
        false
      end

      # An array of arrays of conditions. Each item in the outside array corresponds to a reflection
      # in the #chain. The inside arrays are simply conditions (and each condition may itself be
      # a hash, array, arel predicate, etc...)
      def conditions
        [[options[:conditions]].compact]
      end

      alias :source_macro :macro

      def has_inverse?
        @options[:inverse_of]
      end

      def inverse_of
        if has_inverse?
          @inverse_of ||= klass.reflect_on_association(options[:inverse_of])
        end
      end

      def polymorphic_inverse_of(associated_class)
        if has_inverse?
          if inverse_relationship = associated_class.reflect_on_association(options[:inverse_of])
            inverse_relationship
          else
            raise InverseOfAssociationNotFoundError.new(self, associated_class)
          end
        end
      end

      # Returns whether or not this association reflection is for a collection
      # association. Returns +true+ if the +macro+ is either +has_many+ or
      # +has_and_belongs_to_many+, +false+ otherwise.
      def collection?
        @collection
      end

      # Returns whether or not the association should be validated as part of
      # the parent's validation.
      #
      # Unless you explicitly disable validation with
      # <tt>:validate => false</tt>, validation will take place when:
      #
      # * you explicitly enable validation; <tt>:validate => true</tt>
      # * you use autosave; <tt>:autosave => true</tt>
      # * the association is a +has_many+ association
      def validate?
        !options[:validate].nil? ? options[:validate] : (options[:autosave] == true || macro == :has_many)
      end

      # Returns +true+ if +self+ is a +belongs_to+ reflection.
      def belongs_to?
        macro == :belongs_to
      end

      def association_class
        case macro
        when :belongs_to
          if options[:polymorphic]
            Associations::BelongsToPolymorphicAssociation
          else
            Associations::BelongsToAssociation
          end
        when :has_and_belongs_to_many
          Associations::HasAndBelongsToManyAssociation
        when :has_many
          if options[:through]
            Associations::HasManyThroughAssociation
          else
            Associations::HasManyAssociation
          end
        when :has_one
          if options[:through]
            Associations::HasOneThroughAssociation
          else
            Associations::HasOneAssociation
          end
        end
      end

      private
        def derive_class_name
          class_name = name.to_s.camelize
          class_name = class_name.singularize if collection?
          class_name
        end

        def derive_foreign_key
          if belongs_to?
            "#{name}_id"
          elsif options[:as]
            "#{options[:as]}_id"
          else
            active_record.name.foreign_key
          end
        end

        def primary_key(klass)
          klass.primary_key || raise(UnknownPrimaryKey.new(klass))
        end
    end

    # Holds all the meta-data about a :through association as it was specified
    # in the Active Record class.
    class ThroughReflection < AssociationReflection #:nodoc:
      delegate :foreign_key, :foreign_type, :association_foreign_key,
               :active_record_primary_key, :type, :to => :source_reflection

      # Gets the source of the through reflection. It checks both a singularized
      # and pluralized form for <tt>:belongs_to</tt> or <tt>:has_many</tt>.
      #
      #   class Post < ActiveRecord::Base
      #     has_many :taggings
      #     has_many :tags, :through => :taggings
      #   end
      #
      def source_reflection
        @source_reflection ||= source_reflection_names.collect { |name| through_reflection.klass.reflect_on_association(name) }.compact.first
      end

      # Returns the AssociationReflection object specified in the <tt>:through</tt> option
      # of a HasManyThrough or HasOneThrough association.
      #
      #   class Post < ActiveRecord::Base
      #     has_many :taggings
      #     has_many :tags, :through => :taggings
      #   end
      #
      #   tags_reflection = Post.reflect_on_association(:tags)
      #   taggings_reflection = tags_reflection.through_reflection
      #
      def through_reflection
        @through_reflection ||= active_record.reflect_on_association(options[:through])
      end

      # Returns an array of reflections which are involved in this association. Each item in the
      # array corresponds to a table which will be part of the query for this association.
      #
      # The chain is built by recursively calling #chain on the source reflection and the through
      # reflection. The base case for the recursion is a normal association, which just returns
      # [self] as its #chain.
      def chain
        @chain ||= begin
          chain = source_reflection.chain + through_reflection.chain
          chain[0] = self # Use self so we don't lose the information from :source_type
          chain
        end
      end

      # Consider the following example:
      #
      #   class Person
      #     has_many :articles
      #     has_many :comment_tags, :through => :articles
      #   end
      #
      #   class Article
      #     has_many :comments
      #     has_many :comment_tags, :through => :comments, :source => :tags
      #   end
      #
      #   class Comment
      #     has_many :tags
      #   end
      #
      # There may be conditions on Person.comment_tags, Article.comment_tags and/or Comment.tags,
      # but only Comment.tags will be represented in the #chain. So this method creates an array
      # of conditions corresponding to the chain. Each item in the #conditions array corresponds
      # to an item in the #chain, and is itself an array of conditions from an arbitrary number
      # of relevant reflections, plus any :source_type or polymorphic :as constraints.
      def conditions
        @conditions ||= begin
          conditions = source_reflection.conditions.map { |c| c.dup }

          # Add to it the conditions from this reflection if necessary.
          conditions.first << options[:conditions] if options[:conditions]

          through_conditions = through_reflection.conditions

          if options[:source_type]
            through_conditions.first << { foreign_type => options[:source_type] }
          end

          # Recursively fill out the rest of the array from the through reflection
          conditions += through_conditions

          # And return
          conditions
        end
      end

      # The macro used by the source association
      def source_macro
        source_reflection.source_macro
      end

      # A through association is nested if there would be more than one join table
      def nested?
        chain.length > 2 || through_reflection.macro == :has_and_belongs_to_many
      end

      # We want to use the klass from this reflection, rather than just delegate straight to
      # the source_reflection, because the source_reflection may be polymorphic. We still
      # need to respect the source_reflection's :primary_key option, though.
      def association_primary_key(klass = nil)
        # Get the "actual" source reflection if the immediate source reflection has a
        # source reflection itself
        source_reflection = self.source_reflection
        while source_reflection.source_reflection
          source_reflection = source_reflection.source_reflection
        end

        source_reflection.options[:primary_key] || primary_key(klass || self.klass)
      end

      # Gets an array of possible <tt>:through</tt> source reflection names:
      #
      #   [:singularized, :pluralized]
      #
      def source_reflection_names
        @source_reflection_names ||= (options[:source] ? [options[:source]] : [name.to_s.singularize, name]).collect { |n| n.to_sym }
      end

      def source_options
        source_reflection.options
      end

      def through_options
        through_reflection.options
      end

      def check_validity!
        if through_reflection.nil?
          raise HasManyThroughAssociationNotFoundError.new(active_record.name, self)
        end

        if through_reflection.options[:polymorphic]
          raise HasManyThroughAssociationPolymorphicThroughError.new(active_record.name, self)
        end

        if source_reflection.nil?
          raise HasManyThroughSourceAssociationNotFoundError.new(self)
        end

        if options[:source_type] && source_reflection.options[:polymorphic].nil?
          raise HasManyThroughAssociationPointlessSourceTypeError.new(active_record.name, self, source_reflection)
        end

        if source_reflection.options[:polymorphic] && options[:source_type].nil?
          raise HasManyThroughAssociationPolymorphicSourceError.new(active_record.name, self, source_reflection)
        end

        if macro == :has_one && through_reflection.collection?
          raise HasOneThroughCantAssociateThroughCollection.new(active_record.name, self, through_reflection)
        end

        check_validity_of_inverse!
      end

      private
        def derive_class_name
          # get the class_name of the belongs_to association of the through reflection
          options[:source_type] || source_reflection.class_name
        end
    end
  end
end
require 'active_support/core_ext/object/blank'

module ActiveRecord
  module Batches
    # Yields each record that was found by the find +options+. The find is
    # performed by find_in_batches with a batch size of 1000 (or as
    # specified by the <tt>:batch_size</tt> option).
    #
    # Example:
    #
    #   Person.where("age > 21").find_each do |person|
    #     person.party_all_night!
    #   end
    #
    # Note: This method is only intended to use for batch processing of
    # large amounts of records that wouldn't fit in memory all at once. If
    # you just need to loop over less than 1000 records, it's probably
    # better just to use the regular find methods.
    def find_each(options = {})
      find_in_batches(options) do |records|
        records.each { |record| yield record }
      end
    end

    # Yields each batch of records that was found by the find +options+ as
    # an array. The size of each batch is set by the <tt>:batch_size</tt>
    # option; the default is 1000.
    #
    # You can control the starting point for the batch processing by
    # supplying the <tt>:start</tt> option. This is especially useful if you
    # want multiple workers dealing with the same processing queue. You can
    # make worker 1 handle all the records between id 0 and 10,000 and
    # worker 2 handle from 10,000 and beyond (by setting the <tt>:start</tt>
    # option on that worker).
    #
    # It's not possible to set the order. That is automatically set to
    # ascending on the primary key ("id ASC") to make the batch ordering
    # work. This also mean that this method only works with integer-based
    # primary keys. You can't set the limit either, that's used to control
    # the batch sizes.
    #
    # Example:
    #
    #   Person.where("age > 21").find_in_batches do |group|
    #     sleep(50) # Make sure it doesn't get too crowded in there!
    #     group.each { |person| person.party_all_night! }
    #   end
    def find_in_batches(options = {})
      relation = self

      unless arel.orders.blank? && arel.taken.blank?
        ActiveRecord::Base.logger.warn("Scoped order and limit are ignored, it's forced to be batch order and batch size")
      end

      if (finder_options = options.except(:start, :batch_size)).present?
        raise "You can't specify an order, it's forced to be #{batch_order}" if options[:order].present?
        raise "You can't specify a limit, it's forced to be the batch_size"  if options[:limit].present?

        relation = apply_finder_options(finder_options)
      end

      start = options.delete(:start).to_i
      batch_size = options.delete(:batch_size) || 1000

      relation = relation.reorder(batch_order).limit(batch_size)
      records = relation.where(table[primary_key].gteq(start)).all

      while records.any?
        records_size = records.size
        primary_key_offset = records.last.id

        yield records

        break if records_size < batch_size

        if primary_key_offset
          records = relation.where(table[primary_key].gt(primary_key_offset)).to_a
        else
          raise "Primary key not included in the custom select clause"
        end
      end
    end

    private

    def batch_order
      "#{quoted_table_name}.#{quoted_primary_key} ASC"
    end
  end
end
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/try'

module ActiveRecord
  module Calculations
    # Count operates using three different approaches.
    #
    # * Count all: By not passing any parameters to count, it will return a count of all the rows for the model.
    # * Count using column: By passing a column name to count, it will return a count of all the
    #   rows for the model with supplied column present.
    # * Count using options will find the row count matched by the options used.
    #
    # The third approach, count using options, accepts an option hash as the only parameter. The options are:
    #
    # * <tt>:conditions</tt>: An SQL fragment like "administrator = 1" or [ "user_name = ?", username ].
    #   See conditions in the intro to ActiveRecord::Base.
    # * <tt>:joins</tt>: Either an SQL fragment for additional joins like "LEFT JOIN comments ON comments.post_id = id"
    #   (rarely needed) or named associations in the same form used for the <tt>:include</tt> option, which will
    #   perform an INNER JOIN on the associated table(s). If the value is a string, then the records
    #   will be returned read-only since they will have attributes that do not correspond to the table's columns.
    #   Pass <tt>:readonly => false</tt> to override.
    # * <tt>:include</tt>: Named associations that should be loaded alongside using LEFT OUTER JOINs.
    #   The symbols named refer to already defined associations. When using named associations, count
    #   returns the number of DISTINCT items for the model you're counting.
    #   See eager loading under Associations.
    # * <tt>:order</tt>: An SQL fragment like "created_at DESC, name" (really only used with GROUP BY calculations).
    # * <tt>:group</tt>: An attribute name by which the result should be grouped. Uses the GROUP BY SQL-clause.
    # * <tt>:select</tt>: By default, this is * as in SELECT * FROM, but can be changed if you, for example,
    #   want to do a join but not include the joined columns.
    # * <tt>:distinct</tt>: Set this to true to make this a distinct calculation, such as
    #   SELECT COUNT(DISTINCT posts.id) ...
    # * <tt>:from</tt> - By default, this is the table name of the class, but can be changed to an
    #   alternate table name (or even the name of a database view).
    #
    # Examples for counting all:
    #   Person.count         # returns the total count of all people
    #
    # Examples for counting by column:
    #   Person.count(:age)  # returns the total count of all people whose age is present in database
    #
    # Examples for count with options:
    #   Person.count(:conditions => "age > 26")
    #
    #   # because of the named association, it finds the DISTINCT count using LEFT OUTER JOIN.
    #   Person.count(:conditions => "age > 26 AND job.salary > 60000", :include => :job)
    #
    #   # finds the number of rows matching the conditions and joins.
    #   Person.count(:conditions => "age > 26 AND job.salary > 60000",
    #                :joins => "LEFT JOIN jobs on jobs.person_id = person.id")
    #
    #   Person.count('id', :conditions => "age > 26") # Performs a COUNT(id)
    #   Person.count(:all, :conditions => "age > 26") # Performs a COUNT(*) (:all is an alias for '*')
    #
    # Note: <tt>Person.count(:all)</tt> will not work because it will use <tt>:all</tt> as the condition.
    # Use Person.count instead.
    def count(column_name = nil, options = {})
      column_name, options = nil, column_name if column_name.is_a?(Hash)
      calculate(:count, column_name, options)
    end

    # Calculates the average value on a given column. Returns +nil+ if there's
    # no row. See +calculate+ for examples with options.
    #
    #   Person.average('age') # => 35.8
    def average(column_name, options = {})
      calculate(:average, column_name, options)
    end

    # Calculates the minimum value on a given column. The value is returned
    # with the same data type of the column, or +nil+ if there's no row. See
    # +calculate+ for examples with options.
    #
    #   Person.minimum('age') # => 7
    def minimum(column_name, options = {})
      calculate(:minimum, column_name, options)
    end

    # Calculates the maximum value on a given column. The value is returned
    # with the same data type of the column, or +nil+ if there's no row. See
    # +calculate+ for examples with options.
    #
    #   Person.maximum('age') # => 93
    def maximum(column_name, options = {})
      calculate(:maximum, column_name, options)
    end

    # Calculates the sum of values on a given column. The value is returned
    # with the same data type of the column, 0 if there's no row. See
    # +calculate+ for examples with options.
    #
    #   Person.sum('age') # => 4562
    def sum(*args)
      if block_given?
        self.to_a.sum(*args) {|*block_args| yield(*block_args)}
      else
        calculate(:sum, *args)
      end
    end

    # This calculates aggregate values in the given column. Methods for count, sum, average,
    # minimum, and maximum have been added as shortcuts. Options such as <tt>:conditions</tt>,
    # <tt>:order</tt>, <tt>:group</tt>, <tt>:having</tt>, and <tt>:joins</tt> can be passed to customize the query.
    #
    # There are two basic forms of output:
    #   * Single aggregate value: The single value is type cast to Fixnum for COUNT, Float
    #     for AVG, and the given column's type for everything else.
    #   * Grouped values: This returns an ordered hash of the values and groups them by the
    #     <tt>:group</tt> option. It takes either a column name, or the name of a belongs_to association.
    #
    #       values = Person.maximum(:age, :group => 'last_name')
    #       puts values["Drake"]
    #       => 43
    #
    #       drake  = Family.find_by_last_name('Drake')
    #       values = Person.maximum(:age, :group => :family) # Person belongs_to :family
    #       puts values[drake]
    #       => 43
    #
    #       values.each do |family, max_age|
    #       ...
    #       end
    #
    # Options:
    # * <tt>:conditions</tt> - An SQL fragment like "administrator = 1" or [ "user_name = ?", username ].
    #   See conditions in the intro to ActiveRecord::Base.
    # * <tt>:include</tt>: Eager loading, see Associations for details. Since calculations don't load anything,
    #   the purpose of this is to access fields on joined tables in your conditions, order, or group clauses.
    # * <tt>:joins</tt> - An SQL fragment for additional joins like "LEFT JOIN comments ON comments.post_id = id".
    #   (Rarely needed).
    #   The records will be returned read-only since they will have attributes that do not correspond to the
    #   table's columns.
    # * <tt>:order</tt> - An SQL fragment like "created_at DESC, name" (really only used with GROUP BY calculations).
    # * <tt>:group</tt> - An attribute name by which the result should be grouped. Uses the GROUP BY SQL-clause.
    # * <tt>:select</tt> - By default, this is * as in SELECT * FROM, but can be changed if you for example
    #   want to do a join, but not include the joined columns.
    # * <tt>:distinct</tt> - Set this to true to make this a distinct calculation, such as
    #   SELECT COUNT(DISTINCT posts.id) ...
    #
    # Examples:
    #   Person.calculate(:count, :all) # The same as Person.count
    #   Person.average(:age) # SELECT AVG(age) FROM people...
    #   Person.minimum(:age, :conditions => ['last_name != ?', 'Drake']) # Selects the minimum age for
    #                                                                    # everyone with a last name other than 'Drake'
    #
    #   # Selects the minimum age for any family without any minors
    #   Person.minimum(:age, :having => 'min(age) > 17', :group => :last_name)
    #
    #   Person.sum("2 * age")
    def calculate(operation, column_name, options = {})
      if options.except(:distinct).present?
        apply_finder_options(options.except(:distinct)).calculate(operation, column_name, :distinct => options[:distinct])
      else
        relation = with_default_scope

        if relation.equal?(self)
          if eager_loading? || (includes_values.present? && references_eager_loaded_tables?)
            construct_relation_for_association_calculations.calculate(operation, column_name, options)
          else
            perform_calculation(operation, column_name, options)
          end
        else
          relation.calculate(operation, column_name, options)
        end
      end
    rescue ThrowResult
      0
    end

    # This method is designed to perform select by a single column as direct SQL query
    # Returns <tt>Array</tt> with values of the specified column name
    # The values has same data type as column.
    #
    # Examples:
    #
    #   Person.pluck(:id) # SELECT people.id FROM people
    #   Person.uniq.pluck(:role) # SELECT DISTINCT role FROM people
    #   Person.where(:confirmed => true).limit(5).pluck(:id)
    #
    def pluck(column_name)
      column_name = column_name.to_s
      klass.connection.select_all(select(column_name).arel).map! do |attributes|
        klass.type_cast_attribute(attributes.keys.first, klass.initialize_attributes(attributes))
      end
    end

    private

    def perform_calculation(operation, column_name, options = {})
      operation = operation.to_s.downcase

      distinct = options[:distinct]

      if operation == "count"
        column_name ||= (select_for_count || :all)

        unless arel.ast.grep(Arel::Nodes::OuterJoin).empty?
          distinct = true
        end

        column_name = primary_key if column_name == :all && distinct

        distinct = nil if column_name =~ /\s*DISTINCT\s+/i
      end

      if @group_values.any?
        execute_grouped_calculation(operation, column_name, distinct)
      else
        execute_simple_calculation(operation, column_name, distinct)
      end
    end

    def aggregate_column(column_name)
      if @klass.column_names.include?(column_name.to_s)
        Arel::Attribute.new(@klass.unscoped.table, column_name)
      else
        Arel.sql(column_name == :all ? "*" : column_name.to_s)
      end
    end

    def operation_over_aggregate_column(column, operation, distinct)
      operation == 'count' ? column.count(distinct) : column.send(operation)
    end

    def execute_simple_calculation(operation, column_name, distinct) #:nodoc:
      # Postgresql doesn't like ORDER BY when there are no GROUP BY
      relation = reorder(nil)

      if operation == "count" && (relation.limit_value || relation.offset_value)
        # Shortcut when limit is zero.
        return 0 if relation.limit_value == 0

        query_builder = build_count_subquery(relation, column_name, distinct)
      else
        column = aggregate_column(column_name)

        select_value = operation_over_aggregate_column(column, operation, distinct)

        relation.select_values = [select_value]

        query_builder = relation.arel
      end

      type_cast_calculated_value(@klass.connection.select_value(query_builder), column_for(column_name), operation)
    end

    def execute_grouped_calculation(operation, column_name, distinct) #:nodoc:
      group_attrs = @group_values

      if group_attrs.first.respond_to?(:to_sym)
        association  = @klass.reflect_on_association(group_attrs.first.to_sym)
        associated   = group_attrs.size == 1 && association && association.macro == :belongs_to # only count belongs_to associations
        group_fields = Array(associated ? association.foreign_key : group_attrs)
      else
        group_fields = group_attrs
      end

      group_aliases = group_fields.map { |field| column_alias_for(field) }
      group_columns = group_aliases.zip(group_fields).map { |aliaz,field|
        [aliaz, column_for(field)]
      }

      group = @klass.connection.adapter_name == 'FrontBase' ? group_aliases : group_fields

      if operation == 'count' && column_name == :all
        aggregate_alias = 'count_all'
      else
        aggregate_alias = column_alias_for(operation, column_name)
      end

      select_values = [
        operation_over_aggregate_column(
          aggregate_column(column_name),
          operation,
          distinct).as(aggregate_alias)
      ]
      select_values += @select_values unless @having_values.empty?

      select_values.concat group_fields.zip(group_aliases).map { |field,aliaz|
        if field.respond_to?(:as)
          field.as(aliaz)
        else
          "#{field} AS #{aliaz}"
        end
      }

      relation = except(:group).group(group)
      relation.select_values = select_values

      calculated_data = @klass.connection.select_all(relation)

      if association
        key_ids     = calculated_data.collect { |row| row[group_aliases.first] }
        key_records = association.klass.base_class.find(key_ids)
        key_records = Hash[key_records.map { |r| [r.id, r] }]
      end

      ActiveSupport::OrderedHash[calculated_data.map do |row|
        key = group_columns.map { |aliaz, column|
          type_cast_calculated_value(row[aliaz], column)
        }
        key = key.first if key.size == 1
        key = key_records[key] if associated
        [key, type_cast_calculated_value(row[aggregate_alias], column_for(column_name), operation)]
      end]
    end

    # Converts the given keys to the value that the database adapter returns as
    # a usable column name:
    #
    #   column_alias_for("users.id")                 # => "users_id"
    #   column_alias_for("sum(id)")                  # => "sum_id"
    #   column_alias_for("count(distinct users.id)") # => "count_distinct_users_id"
    #   column_alias_for("count(*)")                 # => "count_all"
    #   column_alias_for("count", "id")              # => "count_id"
    def column_alias_for(*keys)
      keys.map! {|k| k.respond_to?(:to_sql) ? k.to_sql : k}
      table_name = keys.join(' ')
      table_name.downcase!
      table_name.gsub!(/\*/, 'all')
      table_name.gsub!(/\W+/, ' ')
      table_name.strip!
      table_name.gsub!(/ +/, '_')

      @klass.connection.table_alias_for(table_name)
    end

    def column_for(field)
      field_name = field.respond_to?(:name) ? field.name.to_s : field.to_s.split('.').last
      @klass.columns.detect { |c| c.name.to_s == field_name }
    end

    def type_cast_calculated_value(value, column, operation = nil)
      case operation
        when 'count'   then value.to_i
        when 'sum'     then type_cast_using_column(value || '0', column)
        when 'average' then value.respond_to?(:to_d) ? value.to_d : value
        else type_cast_using_column(value, column)
      end
    end

    def type_cast_using_column(value, column)
      column ? column.type_cast(value) : value
    end

    def select_for_count
      if @select_values.present?
        select = @select_values.join(", ")
        select if select !~ /(,|\*)/
      end
    end

    def build_count_subquery(relation, column_name, distinct)
      column_alias = Arel.sql('count_column')
      subquery_alias = Arel.sql('subquery_for_count')

      aliased_column = aggregate_column(column_name == :all ? 1 : column_name).as(column_alias)
      relation.select_values = [aliased_column]
      subquery = relation.arel.as(subquery_alias)

      sm = Arel::SelectManager.new relation.engine
      select_value = operation_over_aggregate_column(column_alias, 'count', distinct)
      sm.project(select_value).from(subquery)
    end
  end
end
require 'active_support/core_ext/module/delegation'

module ActiveRecord
  module Delegation
    # Set up common delegations for performance (avoids method_missing)
    delegate :to_xml, :to_yaml, :length, :collect, :map, :each, :all?, :include?, :to_ary, :to => :to_a
    delegate :table_name, :quoted_table_name, :primary_key, :quoted_primary_key,
             :connection, :columns_hash, :auto_explain_threshold_in_seconds, :to => :klass

    def self.delegate_to_scoped_klass(method)
      if method.to_s =~ /\A[a-zA-Z_]\w*[!?]?\z/
        module_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{method}(*args, &block)
            scoping { @klass.#{method}(*args, &block) }
          end
        RUBY
      else
        module_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{method}(*args, &block)
            scoping { @klass.send(#{method.inspect}, *args, &block) }
          end
        RUBY
      end
    end

    def respond_to?(method, include_private = false)
      super || Array.method_defined?(method) ||
        @klass.respond_to?(method, include_private) ||
        arel.respond_to?(method, include_private)
    end

    protected

    def method_missing(method, *args, &block)
      if @klass.respond_to?(method)
        ::ActiveRecord::Delegation.delegate_to_scoped_klass(method)
        scoping { @klass.send(method, *args, &block) }
      elsif Array.method_defined?(method)
        ::ActiveRecord::Delegation.delegate method, :to => :to_a
        to_a.send(method, *args, &block)
      elsif arel.respond_to?(method)
        ::ActiveRecord::Delegation.delegate method, :to => :arel
        arel.send(method, *args, &block)
      else
        super
      end
    end
  end
end
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/hash/indifferent_access'

module ActiveRecord
  module FinderMethods
    # Find operates with four different retrieval approaches:
    #
    # * Find by id - This can either be a specific id (1), a list of ids (1, 5, 6), or an array of ids ([5, 6, 10]).
    #   If no record can be found for all of the listed ids, then RecordNotFound will be raised.
    # * Find first - This will return the first record matched by the options used. These options can either be specific
    #   conditions or merely an order. If no record can be matched, +nil+ is returned. Use
    #   <tt>Model.find(:first, *args)</tt> or its shortcut <tt>Model.first(*args)</tt>.
    # * Find last - This will return the last record matched by the options used. These options can either be specific
    #   conditions or merely an order. If no record can be matched, +nil+ is returned. Use
    #   <tt>Model.find(:last, *args)</tt> or its shortcut <tt>Model.last(*args)</tt>.
    # * Find all - This will return all the records matched by the options used.
    #   If no records are found, an empty array is returned. Use
    #   <tt>Model.find(:all, *args)</tt> or its shortcut <tt>Model.all(*args)</tt>.
    #
    # All approaches accept an options hash as their last parameter.
    #
    # ==== Options
    #
    # * <tt>:conditions</tt> - An SQL fragment like "administrator = 1", <tt>["user_name = ?", username]</tt>,
    #   or <tt>["user_name = :user_name", { :user_name => user_name }]</tt>. See conditions in the intro.
    # * <tt>:order</tt> - An SQL fragment like "created_at DESC, name".
    # * <tt>:group</tt> - An attribute name by which the result should be grouped. Uses the <tt>GROUP BY</tt> SQL-clause.
    # * <tt>:having</tt> - Combined with +:group+ this can be used to filter the records that a
    #   <tt>GROUP BY</tt> returns. Uses the <tt>HAVING</tt> SQL-clause.
    # * <tt>:limit</tt> - An integer determining the limit on the number of rows that should be returned.
    # * <tt>:offset</tt> - An integer determining the offset from where the rows should be fetched. So at 5,
    #   it would skip rows 0 through 4.
    # * <tt>:joins</tt> - Either an SQL fragment for additional joins like "LEFT JOIN comments ON comments.post_id = id" (rarely needed),
    #   named associations in the same form used for the <tt>:include</tt> option, which will perform an
    #   <tt>INNER JOIN</tt> on the associated table(s),
    #   or an array containing a mixture of both strings and named associations.
    #   If the value is a string, then the records will be returned read-only since they will
    #   have attributes that do not correspond to the table's columns.
    #   Pass <tt>:readonly => false</tt> to override.
    # * <tt>:include</tt> - Names associations that should be loaded alongside. The symbols named refer
    #   to already defined associations. See eager loading under Associations.
    # * <tt>:select</tt> - By default, this is "*" as in "SELECT * FROM", but can be changed if you,
    #   for example, want to do a join but not include the joined columns. Takes a string with the SELECT SQL fragment (e.g. "id, name").
    # * <tt>:from</tt> - By default, this is the table name of the class, but can be changed
    #   to an alternate table name (or even the name of a database view).
    # * <tt>:readonly</tt> - Mark the returned records read-only so they cannot be saved or updated.
    # * <tt>:lock</tt> - An SQL fragment like "FOR UPDATE" or "LOCK IN SHARE MODE".
    #   <tt>:lock => true</tt> gives connection's default exclusive lock, usually "FOR UPDATE".
    #
    # ==== Examples
    #
    #   # find by id
    #   Person.find(1)       # returns the object for ID = 1
    #   Person.find(1, 2, 6) # returns an array for objects with IDs in (1, 2, 6)
    #   Person.find([7, 17]) # returns an array for objects with IDs in (7, 17)
    #   Person.find([1])     # returns an array for the object with ID = 1
    #   Person.where("administrator = 1").order("created_on DESC").find(1)
    #
    # Note that returned records may not be in the same order as the ids you
    # provide since database rows are unordered. Give an explicit <tt>:order</tt>
    # to ensure the results are sorted.
    #
    # ==== Examples
    #
    #   # find first
    #   Person.first # returns the first object fetched by SELECT * FROM people
    #   Person.where(["user_name = ?", user_name]).first
    #   Person.where(["user_name = :u", { :u => user_name }]).first
    #   Person.order("created_on DESC").offset(5).first
    #
    #   # find last
    #   Person.last # returns the last object fetched by SELECT * FROM people
    #   Person.where(["user_name = ?", user_name]).last
    #   Person.order("created_on DESC").offset(5).last
    #
    #   # find all
    #   Person.all # returns an array of objects for all the rows fetched by SELECT * FROM people
    #   Person.where(["category IN (?)", categories]).limit(50).all
    #   Person.where({ :friends => ["Bob", "Steve", "Fred"] }).all
    #   Person.offset(10).limit(10).all
    #   Person.includes([:account, :friends]).all
    #   Person.group("category").all
    #
    # Example for find with a lock: Imagine two concurrent transactions:
    # each will read <tt>person.visits == 2</tt>, add 1 to it, and save, resulting
    # in two saves of <tt>person.visits = 3</tt>. By locking the row, the second
    # transaction has to wait until the first is finished; we get the
    # expected <tt>person.visits == 4</tt>.
    #
    #   Person.transaction do
    #     person = Person.lock(true).find(1)
    #     person.visits += 1
    #     person.save!
    #   end
    def find(*args)
      return to_a.find { |*block_args| yield(*block_args) } if block_given?

      options = args.extract_options!

      if options.present?
        apply_finder_options(options).find(*args)
      else
        case args.first
        when :first, :last, :all
          send(args.first)
        else
          find_with_ids(*args)
        end
      end
    end

    # A convenience wrapper for <tt>find(:first, *args)</tt>. You can pass in all the
    # same arguments to this method as you can to <tt>find(:first)</tt>.
    def first(*args)
      if args.any?
        if args.first.kind_of?(Integer) || (loaded? && !args.first.kind_of?(Hash))
          limit(*args).to_a
        else
          apply_finder_options(args.first).first
        end
      else
        find_first
      end
    end

    # Same as +first+ but raises <tt>ActiveRecord::RecordNotFound</tt> if no record
    # is found. Note that <tt>first!</tt> accepts no arguments.
    def first!
      first or raise RecordNotFound
    end

    # A convenience wrapper for <tt>find(:last, *args)</tt>. You can pass in all the
    # same arguments to this method as you can to <tt>find(:last)</tt>.
    def last(*args)
      if args.any?
        if args.first.kind_of?(Integer) || (loaded? && !args.first.kind_of?(Hash))
          if order_values.empty?
            order("#{primary_key} DESC").limit(*args).reverse
          else
            to_a.last(*args)
          end
        else
          apply_finder_options(args.first).last
        end
      else
        find_last
      end
    end

    # Same as +last+ but raises <tt>ActiveRecord::RecordNotFound</tt> if no record
    # is found. Note that <tt>last!</tt> accepts no arguments.
    def last!
      last or raise RecordNotFound
    end

    # A convenience wrapper for <tt>find(:all, *args)</tt>. You can pass in all the
    # same arguments to this method as you can to <tt>find(:all)</tt>.
    def all(*args)
      args.any? ? apply_finder_options(args.first).to_a : to_a
    end

    # Returns true if a record exists in the table that matches the +id+ or
    # conditions given, or false otherwise. The argument can take five forms:
    #
    # * Integer - Finds the record with this primary key.
    # * String - Finds the record with a primary key corresponding to this
    #   string (such as <tt>'5'</tt>).
    # * Array - Finds the record that matches these +find+-style conditions
    #   (such as <tt>['color = ?', 'red']</tt>).
    # * Hash - Finds the record that matches these +find+-style conditions
    #   (such as <tt>{:color => 'red'}</tt>).
    # * No args - Returns false if the table is empty, true otherwise.
    #
    # For more information about specifying conditions as a Hash or Array,
    # see the Conditions section in the introduction to ActiveRecord::Base.
    #
    # Note: You can't pass in a condition as a string (like <tt>name =
    # 'Jamie'</tt>), since it would be sanitized and then queried against
    # the primary key column, like <tt>id = 'name = \'Jamie\''</tt>.
    #
    # ==== Examples
    #   Person.exists?(5)
    #   Person.exists?('5')
    #   Person.exists?(:name => "David")
    #   Person.exists?(['name LIKE ?', "%#{query}%"])
    #   Person.exists?
    def exists?(id = false)
      id = id.id if ActiveRecord::Base === id
      return false if id.nil?

      join_dependency = construct_join_dependency_for_association_find
      relation = construct_relation_for_association_find(join_dependency)
      relation = relation.except(:select, :order).select("1 AS one").limit(1)

      case id
      when Array, Hash
        relation = relation.where(id)
      else
        relation = relation.where(table[primary_key].eq(id)) if id
      end

      connection.select_value(relation, "#{name} Exists") ? true : false
    rescue ThrowResult
      false
    end

    protected

    def find_with_associations
      join_dependency = construct_join_dependency_for_association_find
      relation = construct_relation_for_association_find(join_dependency)
      rows = connection.select_all(relation, 'SQL', relation.bind_values.dup)
      join_dependency.instantiate(rows)
    rescue ThrowResult
      []
    end

    def construct_join_dependency_for_association_find
      including = (@eager_load_values + @includes_values).uniq
      ActiveRecord::Associations::JoinDependency.new(@klass, including, [])
    end

    def construct_relation_for_association_calculations
      including = (@eager_load_values + @includes_values).uniq
      join_dependency = ActiveRecord::Associations::JoinDependency.new(@klass, including, arel.froms.first)
      relation = except(:includes, :eager_load, :preload)
      apply_join_dependency(relation, join_dependency)
    end

    def construct_relation_for_association_find(join_dependency)
      relation = except(:includes, :eager_load, :preload, :select).select(join_dependency.columns)
      apply_join_dependency(relation, join_dependency)
    end

    def apply_join_dependency(relation, join_dependency)
      join_dependency.join_associations.each do |association|
        relation = association.join_relation(relation)
      end

      limitable_reflections = using_limitable_reflections?(join_dependency.reflections)

      if !limitable_reflections && relation.limit_value
        limited_id_condition = construct_limited_ids_condition(relation.except(:select))
        relation = relation.where(limited_id_condition)
      end

      relation = relation.except(:limit, :offset) unless limitable_reflections

      relation
    end

    def construct_limited_ids_condition(relation)
      orders = relation.order_values.map { |val| val.presence }.compact
      values = @klass.connection.distinct("#{@klass.connection.quote_table_name table_name}.#{primary_key}", orders)

      relation = relation.dup

      ids_array = relation.select(values).collect {|row| row[primary_key]}
      ids_array.empty? ? raise(ThrowResult) : table[primary_key].in(ids_array)
    end

    def find_by_attributes(match, attributes, *args)
      conditions = Hash[attributes.map {|a| [a, args[attributes.index(a)]]}]
      result = where(conditions).send(match.finder)

      if match.bang? && result.blank?
        raise RecordNotFound, "Couldn't find #{@klass.name} with #{conditions.to_a.collect {|p| p.join(' = ')}.join(', ')}"
      else
        yield(result) if block_given?
        result
      end
    end

    def find_or_instantiator_by_attributes(match, attributes, *args)
      options = args.size > 1 && args.last(2).all?{ |a| a.is_a?(Hash) } ? args.extract_options! : {}
      protected_attributes_for_create, unprotected_attributes_for_create = {}, {}
      args.each_with_index do |arg, i|
        if arg.is_a?(Hash)
          protected_attributes_for_create = args[i].with_indifferent_access
        else
          unprotected_attributes_for_create[attributes[i]] = args[i]
        end
      end

      conditions = (protected_attributes_for_create.merge(unprotected_attributes_for_create)).slice(*attributes).symbolize_keys

      record = where(conditions).first

      unless record
        record = @klass.new(protected_attributes_for_create, options) do |r|
          r.assign_attributes(unprotected_attributes_for_create, :without_protection => true)
        end
        yield(record) if block_given?
        record.send(match.save_method) if match.save_record?
      end

      record
    end

    def find_with_ids(*ids)
      return to_a.find { |*block_args| yield(*block_args) } if block_given?

      expects_array = ids.first.kind_of?(Array)
      return ids.first if expects_array && ids.first.empty?

      ids = ids.flatten.compact.uniq

      case ids.size
      when 0
        raise RecordNotFound, "Couldn't find #{@klass.name} without an ID"
      when 1
        result = find_one(ids.first)
        expects_array ? [ result ] : result
      else
        find_some(ids)
      end
    end

    def find_one(id)
      id = id.id if ActiveRecord::Base === id

      if IdentityMap.enabled? && where_values.blank? &&
        limit_value.blank? && order_values.blank? &&
        includes_values.blank? && preload_values.blank? &&
        readonly_value.nil? && joins_values.blank? &&
        !@klass.locking_enabled? &&
        record = IdentityMap.get(@klass, id)
        return record
      end

      column = columns_hash[primary_key]

      substitute = connection.substitute_at(column, @bind_values.length)
      relation = where(table[primary_key].eq(substitute))
      relation.bind_values = [[column, id]]
      record = relation.first

      unless record
        conditions = arel.where_sql
        conditions = " [#{conditions}]" if conditions
        raise RecordNotFound, "Couldn't find #{@klass.name} with #{primary_key}=#{id}#{conditions}"
      end

      record
    end

    def find_some(ids)
      result = where(table[primary_key].in(ids)).all

      expected_size =
        if @limit_value && ids.size > @limit_value
          @limit_value
        else
          ids.size
        end

      # 11 ids with limit 3, offset 9 should give 2 results.
      if @offset_value && (ids.size - @offset_value < expected_size)
        expected_size = ids.size - @offset_value
      end

      if result.size == expected_size
        result
      else
        conditions = arel.where_sql
        conditions = " [#{conditions}]" if conditions

        error = "Couldn't find all #{@klass.name.pluralize} with IDs "
        error << "(#{ids.join(", ")})#{conditions} (found #{result.size} results, but was looking for #{expected_size})"
        raise RecordNotFound, error
      end
    end

    def find_first
      if loaded?
        @records.first
      else
        @first ||= limit(1).to_a[0]
      end
    end

    def find_last
      if loaded?
        @records.last
      else
        @last ||=
          if offset_value || limit_value
            to_a.last
          else
            reverse_order.limit(1).to_a[0]
          end
      end
    end

    def using_limitable_reflections?(reflections)
      reflections.none? { |r| r.collection? }
    end
  end
end
module ActiveRecord
  class PredicateBuilder # :nodoc:
    def self.build_from_hash(engine, attributes, default_table, allow_table_name = true)
      predicates = attributes.map do |column, value|
        table = default_table

        if allow_table_name && value.is_a?(Hash)
          table = Arel::Table.new(column, engine)

          if value.empty?
            '1 = 2'
          else
            build_from_hash(engine, value, table, false)
          end
        else
          column = column.to_s

          if allow_table_name && column.include?('.')
            table_name, column = column.split('.', 2)
            table = Arel::Table.new(table_name, engine)
          end

          attribute = table[column.to_sym]

          case value
          when ActiveRecord::Relation
            value = value.select(value.klass.arel_table[value.klass.primary_key]) if value.select_values.empty?
            attribute.in(value.arel.ast)
          when Array, ActiveRecord::Associations::CollectionProxy
            values = value.to_a.map {|x| x.is_a?(ActiveRecord::Base) ? x.id : x}
            ranges, values = values.partition {|v| v.is_a?(Range) || v.is_a?(Arel::Relation)}

            array_predicates = ranges.map {|range| attribute.in(range)}

            if values.include?(nil)
              values = values.compact
              if values.empty?
                array_predicates << attribute.eq(nil)
              else
                array_predicates << attribute.in(values.compact).or(attribute.eq(nil))
              end
            else
              array_predicates << attribute.in(values)
            end

            array_predicates.inject {|composite, predicate| composite.or(predicate)}
          when Range, Arel::Relation
            attribute.in(value)
          when ActiveRecord::Base
            attribute.eq(value.id)
          when Class
            # FIXME: I think we need to deprecate this behavior
            attribute.eq(value.name)
          when Integer, ActiveSupport::Duration
            # Arel treats integers as literals, but they should be quoted when compared with strings
            column = engine.connection.schema_cache.columns_hash[table.name][attribute.name.to_s]
            attribute.eq(Arel::Nodes::SqlLiteral.new(engine.connection.quote(value, column)))
          else
            attribute.eq(value)
          end
        end
      end

      predicates.flatten
    end
  end
end
require 'active_support/core_ext/array/wrap'
require 'active_support/core_ext/object/blank'

module ActiveRecord
  module QueryMethods
    extend ActiveSupport::Concern

    attr_accessor :includes_values, :eager_load_values, :preload_values,
                  :select_values, :group_values, :order_values, :joins_values,
                  :where_values, :having_values, :bind_values,
                  :limit_value, :offset_value, :lock_value, :readonly_value, :create_with_value,
                  :from_value, :reordering_value, :reverse_order_value,
                  :uniq_value

    def includes(*args)
      args.reject! {|a| a.blank? }

      return self if args.empty?

      relation = clone
      relation.includes_values = (relation.includes_values + args).flatten.uniq
      relation
    end

    def eager_load(*args)
      return self if args.blank?

      relation = clone
      relation.eager_load_values += args
      relation
    end

    def preload(*args)
      return self if args.blank?

      relation = clone
      relation.preload_values += args
      relation
    end

    # Works in two unique ways.
    #
    # First: takes a block so it can be used just like Array#select.
    #
    #   Model.scoped.select { |m| m.field == value }
    #
    # This will build an array of objects from the database for the scope,
    # converting them into an array and iterating through them using Array#select.
    #
    # Second: Modifies the SELECT statement for the query so that only certain
    # fields are retrieved:
    #
    #   >> Model.select(:field)
    #   => [#<Model field:value>]
    #
    # Although in the above example it looks as though this method returns an
    # array, it actually returns a relation object and can have other query
    # methods appended to it, such as the other methods in ActiveRecord::QueryMethods.
    #
    # The argument to the method can also be an array of fields.
    #
    #   >> Model.select([:field, :other_field, :and_one_more])
    #   => [#<Model field: "value", other_field: "value", and_one_more: "value">]
    #
    # Any attributes that do not have fields retrieved by a select
    # will raise a ActiveModel::MissingAttributeError when the getter method for that attribute is used:
    #
    #   >> Model.select(:field).first.other_field
    #   => ActiveModel::MissingAttributeError: missing attribute: other_field
    def select(value = Proc.new)
      if block_given?
        to_a.select {|*block_args| value.call(*block_args) }
      else
        relation = clone
        relation.select_values += Array.wrap(value)
        relation
      end
    end

    def group(*args)
      return self if args.blank?

      relation = clone
      relation.group_values += args.flatten
      relation
    end

    def order(*args)
      return self if args.blank?

      relation = clone
      relation.order_values += args.flatten
      relation
    end

    # Replaces any existing order defined on the relation with the specified order.
    #
    #   User.order('email DESC').reorder('id ASC') # generated SQL has 'ORDER BY id ASC'
    #
    # Subsequent calls to order on the same relation will be appended. For example:
    #
    #   User.order('email DESC').reorder('id ASC').order('name ASC')
    #
    # generates a query with 'ORDER BY id ASC, name ASC'.
    #
    def reorder(*args)
      return self if args.blank?

      relation = clone
      relation.reordering_value = true
      relation.order_values = args.flatten
      relation
    end

    def joins(*args)
      return self if args.compact.blank?

      relation = clone

      args.flatten!
      relation.joins_values += args

      relation
    end

    def bind(value)
      relation = clone
      relation.bind_values += [value]
      relation
    end

    def where(opts, *rest)
      return self if opts.blank?

      relation = clone
      relation.where_values += build_where(opts, rest)
      relation
    end

    def having(opts, *rest)
      return self if opts.blank?

      relation = clone
      relation.having_values += build_where(opts, rest)
      relation
    end

    def limit(value)
      relation = clone
      relation.limit_value = value
      relation
    end

    def offset(value)
      relation = clone
      relation.offset_value = value
      relation
    end

    def lock(locks = true)
      relation = clone

      case locks
      when String, TrueClass, NilClass
        relation.lock_value = locks || true
      else
        relation.lock_value = false
      end

      relation
    end

    def readonly(value = true)
      relation = clone
      relation.readonly_value = value
      relation
    end

    def create_with(value)
      relation = clone
      relation.create_with_value = value ? create_with_value.merge(value) : {}
      relation
    end

    def from(value)
      relation = clone
      relation.from_value = value
      relation
    end

    # Specifies whether the records should be unique or not. For example:
    #
    #   User.select(:name)
    #   # => Might return two records with the same name
    #
    #   User.select(:name).uniq
    #   # => Returns 1 record per unique name
    #
    #   User.select(:name).uniq.uniq(false)
    #   # => You can also remove the uniqueness
    def uniq(value = true)
      relation = clone
      relation.uniq_value = value
      relation
    end

    # Used to extend a scope with additional methods, either through
    # a module or through a block provided.
    #
    # The object returned is a relation, which can be further extended.
    #
    # === Using a module
    #
    #   module Pagination
    #     def page(number)
    #       # pagination code goes here
    #     end
    #   end
    #
    #   scope = Model.scoped.extending(Pagination)
    #   scope.page(params[:page])
    #
    # You can also pass a list of modules:
    #
    #   scope = Model.scoped.extending(Pagination, SomethingElse)
    #
    # === Using a block
    #
    #   scope = Model.scoped.extending do
    #     def page(number)
    #       # pagination code goes here
    #     end
    #   end
    #   scope.page(params[:page])
    #
    # You can also use a block and a module list:
    #
    #   scope = Model.scoped.extending(Pagination) do
    #     def per_page(number)
    #       # pagination code goes here
    #     end
    #   end
    def extending(*modules)
      modules << Module.new(&Proc.new) if block_given?

      return self if modules.empty?

      relation = clone
      relation.send(:apply_modules, modules.flatten)
      relation
    end

    def reverse_order
      relation = clone
      relation.reverse_order_value = !relation.reverse_order_value
      relation
    end

    def arel
      @arel ||= with_default_scope.build_arel
    end

    def build_arel
      arel = table.from table

      build_joins(arel, @joins_values) unless @joins_values.empty?

      collapse_wheres(arel, (@where_values - ['']).uniq)

      arel.having(*@having_values.uniq.reject{|h| h.blank?}) unless @having_values.empty?

      arel.take(connection.sanitize_limit(@limit_value)) if @limit_value
      arel.skip(@offset_value.to_i) if @offset_value

      arel.group(*@group_values.uniq.reject{|g| g.blank?}) unless @group_values.empty?

      order = @order_values
      order = reverse_sql_order(order) if @reverse_order_value
      arel.order(*order.uniq.reject{|o| o.blank?}) unless order.empty?

      build_select(arel, @select_values.uniq)

      arel.distinct(@uniq_value)
      arel.from(@from_value) if @from_value
      arel.lock(@lock_value) if @lock_value

      arel
    end

    private

    def custom_join_ast(table, joins)
      joins = joins.reject { |join| join.blank? }

      return [] if joins.empty?

      @implicit_readonly = true

      joins.map do |join|
        case join
        when Array
          join = Arel.sql(join.join(' ')) if array_of_strings?(join)
        when String
          join = Arel.sql(join)
        end
        table.create_string_join(join)
      end
    end

    def collapse_wheres(arel, wheres)
      equalities = wheres.grep(Arel::Nodes::Equality)

      arel.where(Arel::Nodes::And.new(equalities)) unless equalities.empty?

      (wheres - equalities).each do |where|
        where = Arel.sql(where) if String === where
        arel.where(Arel::Nodes::Grouping.new(where))
      end
    end

    def build_where(opts, other = [])
      case opts
      when String, Array
        [@klass.send(:sanitize_sql, other.empty? ? opts : ([opts] + other))]
      when Hash
        attributes = @klass.send(:expand_hash_conditions_for_aggregates, opts)
        PredicateBuilder.build_from_hash(table.engine, attributes, table)
      else
        [opts]
      end
    end

    def build_joins(manager, joins)
      buckets = joins.group_by do |join|
        case join
        when String
          'string_join'
        when Hash, Symbol, Array
          'association_join'
        when ActiveRecord::Associations::JoinDependency::JoinAssociation
          'stashed_join'
        when Arel::Nodes::Join
          'join_node'
        else
          raise 'unknown class: %s' % join.class.name
        end
      end

      association_joins         = buckets['association_join'] || []
      stashed_association_joins = buckets['stashed_join'] || []
      join_nodes                = (buckets['join_node'] || []).uniq
      string_joins              = (buckets['string_join'] || []).map { |x|
        x.strip
      }.uniq

      join_list = join_nodes + custom_join_ast(manager, string_joins)

      join_dependency = ActiveRecord::Associations::JoinDependency.new(
        @klass,
        association_joins,
        join_list
      )

      join_dependency.graft(*stashed_association_joins)

      @implicit_readonly = true unless association_joins.empty? && stashed_association_joins.empty?

      # FIXME: refactor this to build an AST
      join_dependency.join_associations.each do |association|
        association.join_to(manager)
      end

      manager.join_sources.concat join_list

      manager
    end

    def build_select(arel, selects)
      unless selects.empty?
        @implicit_readonly = false
        arel.project(*selects)
      else
        arel.project(@klass.arel_table[Arel.star])
      end
    end

    def apply_modules(modules)
      unless modules.empty?
        @extensions += modules
        modules.each {|extension| extend(extension) }
      end
    end

    def reverse_sql_order(order_query)
      order_query = ["#{quoted_table_name}.#{quoted_primary_key} ASC"] if order_query.empty?

      order_query.map do |o|
        case o
        when Arel::Nodes::Ordering
          o.reverse
        when String, Symbol
          o.to_s.split(',').collect do |s|
            s.strip!
            s.gsub!(/\sasc\Z/i, ' DESC') || s.gsub!(/\sdesc\Z/i, ' ASC') || s.concat(' DESC')
          end
        else
          o
        end
      end.flatten
    end

    def array_of_strings?(o)
      o.is_a?(Array) && o.all?{|obj| obj.is_a?(String)}
    end

  end
end
require 'active_support/core_ext/object/blank'

module ActiveRecord
  module SpawnMethods
    def merge(r)
      return self unless r
      return to_a & r if r.is_a?(Array)

      merged_relation = clone

      r = r.with_default_scope if r.default_scoped? && r.klass != klass

      Relation::ASSOCIATION_METHODS.each do |method|
        value = r.send(:"#{method}_values")

        unless value.empty?
          if method == :includes
            merged_relation = merged_relation.includes(value)
          else
            merged_relation.send(:"#{method}_values=", value)
          end
        end
      end

      (Relation::MULTI_VALUE_METHODS - [:joins, :where, :order]).each do |method|
        value = r.send(:"#{method}_values")
        merged_relation.send(:"#{method}_values=", merged_relation.send(:"#{method}_values") + value) if value.present?
      end

      merged_relation.joins_values += r.joins_values

      merged_wheres = @where_values + r.where_values

      unless @where_values.empty?
        # Remove duplicates, last one wins.
        seen = Hash.new { |h,table| h[table] = {} }
        merged_wheres = merged_wheres.reverse.reject { |w|
          nuke = false
          if w.respond_to?(:operator) && w.operator == :==
            name              = w.left.name
            table             = w.left.relation.name
            nuke              = seen[table][name]
            seen[table][name] = true
          end
          nuke
        }.reverse
      end

      merged_relation.where_values = merged_wheres

      (Relation::SINGLE_VALUE_METHODS - [:lock, :create_with, :reordering]).each do |method|
        value = r.send(:"#{method}_value")
        merged_relation.send(:"#{method}_value=", value) unless value.nil?
      end

      merged_relation.lock_value = r.lock_value unless merged_relation.lock_value

      merged_relation = merged_relation.create_with(r.create_with_value) unless r.create_with_value.empty?

      if (r.reordering_value)
        # override any order specified in the original relation
        merged_relation.reordering_value = true
        merged_relation.order_values = r.order_values
      else
        # merge in order_values from r
        merged_relation.order_values += r.order_values
      end

      # Apply scope extension modules
      merged_relation.send :apply_modules, r.extensions

      merged_relation
    end

    # Removes from the query the condition(s) specified in +skips+.
    #
    # Example:
    #
    #   Post.order('id asc').except(:order)                  # discards the order condition
    #   Post.where('id > 10').order('id asc').except(:where) # discards the where condition but keeps the order
    #
    def except(*skips)
      result = self.class.new(@klass, table)
      result.default_scoped = default_scoped

      ((Relation::ASSOCIATION_METHODS + Relation::MULTI_VALUE_METHODS) - skips).each do |method|
        result.send(:"#{method}_values=", send(:"#{method}_values"))
      end

      (Relation::SINGLE_VALUE_METHODS - skips).each do |method|
        result.send(:"#{method}_value=", send(:"#{method}_value"))
      end

      # Apply scope extension modules
      result.send(:apply_modules, extensions)

      result
    end

    # Removes any condition from the query other than the one(s) specified in +onlies+.
    #
    # Example:
    #
    #   Post.order('id asc').only(:where)         # discards the order condition
    #   Post.order('id asc').only(:where, :order) # uses the specified order
    #
    def only(*onlies)
      result = self.class.new(@klass, table)
      result.default_scoped = default_scoped

      ((Relation::ASSOCIATION_METHODS + Relation::MULTI_VALUE_METHODS) & onlies).each do |method|
        result.send(:"#{method}_values=", send(:"#{method}_values"))
      end

      (Relation::SINGLE_VALUE_METHODS & onlies).each do |method|
        result.send(:"#{method}_value=", send(:"#{method}_value"))
      end

      # Apply scope extension modules
      result.send(:apply_modules, extensions)

      result
    end

    VALID_FIND_OPTIONS = [ :conditions, :include, :joins, :limit, :offset, :extend,
                           :order, :select, :readonly, :group, :having, :from, :lock ]

    def apply_finder_options(options)
      relation = clone
      return relation unless options

      options.assert_valid_keys(VALID_FIND_OPTIONS)
      finders = options.dup
      finders.delete_if { |key, value| value.nil? && key != :limit }

      ([:joins, :select, :group, :order, :having, :limit, :offset, :from, :lock, :readonly] & finders.keys).each do |finder|
        relation = relation.send(finder, finders[finder])
      end

      relation = relation.where(finders[:conditions]) if options.has_key?(:conditions)
      relation = relation.includes(finders[:include]) if options.has_key?(:include)
      relation = relation.extending(finders[:extend]) if options.has_key?(:extend)

      relation
    end

  end
end
# -*- coding: utf-8 -*-
require 'active_support/core_ext/object/blank'

module ActiveRecord
  # = Active Record Relation
  class Relation
    JoinOperation = Struct.new(:relation, :join_class, :on)
    ASSOCIATION_METHODS = [:includes, :eager_load, :preload]
    MULTI_VALUE_METHODS = [:select, :group, :order, :joins, :where, :having, :bind]
    SINGLE_VALUE_METHODS = [:limit, :offset, :lock, :readonly, :from, :reordering, :reverse_order, :uniq]

    include FinderMethods, Calculations, SpawnMethods, QueryMethods, Batches, Explain, Delegation

    attr_reader :table, :klass, :loaded
    attr_accessor :extensions, :default_scoped
    alias :loaded? :loaded
    alias :default_scoped? :default_scoped

    def initialize(klass, table)
      @klass, @table = klass, table

      @implicit_readonly = nil
      @loaded            = false
      @default_scoped    = false

      SINGLE_VALUE_METHODS.each {|v| instance_variable_set(:"@#{v}_value", nil)}
      (ASSOCIATION_METHODS + MULTI_VALUE_METHODS).each {|v| instance_variable_set(:"@#{v}_values", [])}
      @extensions = []
      @create_with_value = {}
    end

    def insert(values)
      primary_key_value = nil

      if primary_key && Hash === values
        primary_key_value = values[values.keys.find { |k|
          k.name == primary_key
        }]

        if !primary_key_value && connection.prefetch_primary_key?(klass.table_name)
          primary_key_value = connection.next_sequence_value(klass.sequence_name)
          values[klass.arel_table[klass.primary_key]] = primary_key_value
        end
      end

      im = arel.create_insert
      im.into @table

      conn = @klass.connection

      substitutes = values.sort_by { |arel_attr,_| arel_attr.name }
      binds       = substitutes.map do |arel_attr, value|
        [@klass.columns_hash[arel_attr.name], value]
      end

      substitutes.each_with_index do |tuple, i|
        tuple[1] = conn.substitute_at(binds[i][0], i)
      end

      if values.empty? # empty insert
        im.values = Arel.sql(connection.empty_insert_statement_value)
      else
        im.insert substitutes
      end

      conn.insert(
        im,
        'SQL',
        primary_key,
        primary_key_value,
        nil,
        binds)
    end

    def new(*args, &block)
      scoping { @klass.new(*args, &block) }
    end

    def initialize_copy(other)
      @bind_values = @bind_values.dup
      reset
    end

    alias build new

    def create(*args, &block)
      scoping { @klass.create(*args, &block) }
    end

    def create!(*args, &block)
      scoping { @klass.create!(*args, &block) }
    end

    # Tries to load the first record; if it fails, then <tt>create</tt> is called with the same arguments as this method.
    #
    # Expects arguments in the same format as <tt>Base.create</tt>.
    #
    # ==== Examples
    #   # Find the first user named Penélope or create a new one.
    #   User.where(:first_name => 'Penélope').first_or_create
    #   # => <User id: 1, first_name: 'Penélope', last_name: nil>
    #
    #   # Find the first user named Penélope or create a new one.
    #   # We already have one so the existing record will be returned.
    #   User.where(:first_name => 'Penélope').first_or_create
    #   # => <User id: 1, first_name: 'Penélope', last_name: nil>
    #
    #   # Find the first user named Scarlett or create a new one with a particular last name.
    #   User.where(:first_name => 'Scarlett').first_or_create(:last_name => 'Johansson')
    #   # => <User id: 2, first_name: 'Scarlett', last_name: 'Johansson'>
    #
    #   # Find the first user named Scarlett or create a new one with a different last name.
    #   # We already have one so the existing record will be returned.
    #   User.where(:first_name => 'Scarlett').first_or_create do |user|
    #     user.last_name = "O'Hara"
    #   end
    #   # => <User id: 2, first_name: 'Scarlett', last_name: 'Johansson'>
    def first_or_create(attributes = nil, options = {}, &block)
      first || create(attributes, options, &block)
    end

    # Like <tt>first_or_create</tt> but calls <tt>create!</tt> so an exception is raised if the created record is invalid.
    #
    # Expects arguments in the same format as <tt>Base.create!</tt>.
    def first_or_create!(attributes = nil, options = {}, &block)
      first || create!(attributes, options, &block)
    end

    # Like <tt>first_or_create</tt> but calls <tt>new</tt> instead of <tt>create</tt>.
    #
    # Expects arguments in the same format as <tt>Base.new</tt>.
    def first_or_initialize(attributes = nil, options = {}, &block)
      first || new(attributes, options, &block)
    end

    # Runs EXPLAIN on the query or queries triggered by this relation and
    # returns the result as a string. The string is formatted imitating the
    # ones printed by the database shell.
    #
    # Note that this method actually runs the queries, since the results of some
    # are needed by the next ones when eager loading is going on.
    #
    # Please see further details in the
    # {Active Record Query Interface guide}[http://edgeguides.rubyonrails.org/active_record_querying.html#running-explain].
    def explain
      _, queries = collecting_queries_for_explain { exec_queries }
      exec_explain(queries)
    end

    def to_a
      # We monitor here the entire execution rather than individual SELECTs
      # because from the point of view of the user fetching the records of a
      # relation is a single unit of work. You want to know if this call takes
      # too long, not if the individual queries take too long.
      #
      # It could be the case that none of the queries involved surpass the
      # threshold, and at the same time the sum of them all does. The user
      # should get a query plan logged in that case.
      logging_query_plan do
        exec_queries
      end
    end

    def exec_queries
      return @records if loaded?

      default_scoped = with_default_scope

      if default_scoped.equal?(self)
        @records = if @readonly_value.nil? && !@klass.locking_enabled?
          eager_loading? ? find_with_associations : @klass.find_by_sql(arel, @bind_values)
        else
          IdentityMap.without do
            eager_loading? ? find_with_associations : @klass.find_by_sql(arel, @bind_values)
          end
        end

        preload = @preload_values
        preload +=  @includes_values unless eager_loading?
        preload.each do |associations|
          ActiveRecord::Associations::Preloader.new(@records, associations).run
        end

        # @readonly_value is true only if set explicitly. @implicit_readonly is true if there
        # are JOINS and no explicit SELECT.
        readonly = @readonly_value.nil? ? @implicit_readonly : @readonly_value
        @records.each { |record| record.readonly! } if readonly
      else
        @records = default_scoped.to_a
      end

      @loaded = true
      @records
    end
    private :exec_queries

    def as_json(options = nil) #:nodoc:
      to_a.as_json(options)
    end

    # Returns size of the records.
    def size
      loaded? ? @records.length : count
    end

    # Returns true if there are no records.
    def empty?
      return @records.empty? if loaded?

      c = count
      c.respond_to?(:zero?) ? c.zero? : c.empty?
    end

    def any?
      if block_given?
        to_a.any? { |*block_args| yield(*block_args) }
      else
        !empty?
      end
    end

    def many?
      if block_given?
        to_a.many? { |*block_args| yield(*block_args) }
      else
        @limit_value ? to_a.many? : size > 1
      end
    end

    # Scope all queries to the current scope.
    #
    # ==== Example
    #
    #   Comment.where(:post_id => 1).scoping do
    #     Comment.first # SELECT * FROM comments WHERE post_id = 1
    #   end
    #
    # Please check unscoped if you want to remove all previous scopes (including
    # the default_scope) during the execution of a block.
    def scoping
      @klass.with_scope(self, :overwrite) { yield }
    end

    # Updates all records with details given if they match a set of conditions supplied, limits and order can
    # also be supplied. This method constructs a single SQL UPDATE statement and sends it straight to the
    # database. It does not instantiate the involved models and it does not trigger Active Record callbacks
    # or validations.
    #
    # ==== Parameters
    #
    # * +updates+ - A string, array, or hash representing the SET part of an SQL statement.
    # * +conditions+ - A string, array, or hash representing the WHERE part of an SQL statement.
    #   See conditions in the intro.
    # * +options+ - Additional options are <tt>:limit</tt> and <tt>:order</tt>, see the examples for usage.
    #
    # ==== Examples
    #
    #   # Update all customers with the given attributes
    #   Customer.update_all :wants_email => true
    #
    #   # Update all books with 'Rails' in their title
    #   Book.update_all "author = 'David'", "title LIKE '%Rails%'"
    #
    #   # Update all avatars migrated more than a week ago
    #   Avatar.update_all ['migrated_at = ?', Time.now.utc], ['migrated_at > ?', 1.week.ago]
    #
    #   # Update all books that match conditions, but limit it to 5 ordered by date
    #   Book.update_all "author = 'David'", "title LIKE '%Rails%'", :order => 'created_at', :limit => 5
    #
    #   # Conditions from the current relation also works
    #   Book.where('title LIKE ?', '%Rails%').update_all(:author => 'David')
    #
    #   # The same idea applies to limit and order
    #   Book.where('title LIKE ?', '%Rails%').order(:created_at).limit(5).update_all(:author => 'David')
    def update_all(updates, conditions = nil, options = {})
      IdentityMap.repository[symbolized_base_class].clear if IdentityMap.enabled?
      if conditions || options.present?
        where(conditions).apply_finder_options(options.slice(:limit, :order)).update_all(updates)
      else
        stmt = Arel::UpdateManager.new(arel.engine)

        stmt.set Arel.sql(@klass.send(:sanitize_sql_for_assignment, updates))
        stmt.table(table)
        stmt.key = table[primary_key]

        if joins_values.any?
          @klass.connection.join_to_update(stmt, arel)
        else
          stmt.take(arel.limit)
          stmt.order(*arel.orders)
          stmt.wheres = arel.constraints
        end

        @klass.connection.update stmt, 'SQL', bind_values
      end
    end

    # Updates an object (or multiple objects) and saves it to the database, if validations pass.
    # The resulting object is returned whether the object was saved successfully to the database or not.
    #
    # ==== Parameters
    #
    # * +id+ - This should be the id or an array of ids to be updated.
    # * +attributes+ - This should be a hash of attributes or an array of hashes.
    #
    # ==== Examples
    #
    #   # Updates one record
    #   Person.update(15, :user_name => 'Samuel', :group => 'expert')
    #
    #   # Updates multiple records
    #   people = { 1 => { "first_name" => "David" }, 2 => { "first_name" => "Jeremy" } }
    #   Person.update(people.keys, people.values)
    def update(id, attributes)
      if id.is_a?(Array)
        id.each.with_index.map {|one_id, idx| update(one_id, attributes[idx])}
      else
        object = find(id)
        object.update_attributes(attributes)
        object
      end
    end

    # Destroys the records matching +conditions+ by instantiating each
    # record and calling its +destroy+ method. Each object's callbacks are
    # executed (including <tt>:dependent</tt> association options and
    # +before_destroy+/+after_destroy+ Observer methods). Returns the
    # collection of objects that were destroyed; each will be frozen, to
    # reflect that no changes should be made (since they can't be
    # persisted).
    #
    # Note: Instantiation, callback execution, and deletion of each
    # record can be time consuming when you're removing many records at
    # once. It generates at least one SQL +DELETE+ query per record (or
    # possibly more, to enforce your callbacks). If you want to delete many
    # rows quickly, without concern for their associations or callbacks, use
    # +delete_all+ instead.
    #
    # ==== Parameters
    #
    # * +conditions+ - A string, array, or hash that specifies which records
    #   to destroy. If omitted, all records are destroyed. See the
    #   Conditions section in the introduction to ActiveRecord::Base for
    #   more information.
    #
    # ==== Examples
    #
    #   Person.destroy_all("last_login < '2004-04-04'")
    #   Person.destroy_all(:status => "inactive")
    #   Person.where(:age => 0..18).destroy_all
    def destroy_all(conditions = nil)
      if conditions
        where(conditions).destroy_all
      else
        to_a.each {|object| object.destroy }.tap { reset }
      end
    end

    # Destroy an object (or multiple objects) that has the given id, the object is instantiated first,
    # therefore all callbacks and filters are fired off before the object is deleted. This method is
    # less efficient than ActiveRecord#delete but allows cleanup methods and other actions to be run.
    #
    # This essentially finds the object (or multiple objects) with the given id, creates a new object
    # from the attributes, and then calls destroy on it.
    #
    # ==== Parameters
    #
    # * +id+ - Can be either an Integer or an Array of Integers.
    #
    # ==== Examples
    #
    #   # Destroy a single object
    #   Todo.destroy(1)
    #
    #   # Destroy multiple objects
    #   todos = [1,2,3]
    #   Todo.destroy(todos)
    def destroy(id)
      if id.is_a?(Array)
        id.map { |one_id| destroy(one_id) }
      else
        find(id).destroy
      end
    end

    # Deletes the records matching +conditions+ without instantiating the records first, and hence not
    # calling the +destroy+ method nor invoking callbacks. This is a single SQL DELETE statement that
    # goes straight to the database, much more efficient than +destroy_all+. Be careful with relations
    # though, in particular <tt>:dependent</tt> rules defined on associations are not honored. Returns
    # the number of rows affected.
    #
    # ==== Parameters
    #
    # * +conditions+ - Conditions are specified the same way as with +find+ method.
    #
    # ==== Example
    #
    #   Post.delete_all("person_id = 5 AND (category = 'Something' OR category = 'Else')")
    #   Post.delete_all(["person_id = ? AND (category = ? OR category = ?)", 5, 'Something', 'Else'])
    #   Post.where(:person_id => 5).where(:category => ['Something', 'Else']).delete_all
    #
    # Both calls delete the affected posts all at once with a single DELETE statement.
    # If you need to destroy dependent associations or call your <tt>before_*</tt> or
    # +after_destroy+ callbacks, use the +destroy_all+ method instead.
    def delete_all(conditions = nil)
      raise ActiveRecordError.new("delete_all doesn't support limit scope") if self.limit_value

      IdentityMap.repository[symbolized_base_class] = {} if IdentityMap.enabled?
      if conditions
        where(conditions).delete_all
      else
        statement = arel.compile_delete
        affected = @klass.connection.delete(statement, 'SQL', bind_values)

        reset
        affected
      end
    end

    # Deletes the row with a primary key matching the +id+ argument, using a
    # SQL +DELETE+ statement, and returns the number of rows deleted. Active
    # Record objects are not instantiated, so the object's callbacks are not
    # executed, including any <tt>:dependent</tt> association options or
    # Observer methods.
    #
    # You can delete multiple rows at once by passing an Array of <tt>id</tt>s.
    #
    # Note: Although it is often much faster than the alternative,
    # <tt>#destroy</tt>, skipping callbacks might bypass business logic in
    # your application that ensures referential integrity or performs other
    # essential jobs.
    #
    # ==== Examples
    #
    #   # Delete a single row
    #   Todo.delete(1)
    #
    #   # Delete multiple rows
    #   Todo.delete([2,3,4])
    def delete(id_or_array)
      IdentityMap.remove_by_id(self.symbolized_base_class, id_or_array) if IdentityMap.enabled?
      where(primary_key => id_or_array).delete_all
    end

    def reload
      reset
      to_a # force reload
      self
    end

    def reset
      @first = @last = @to_sql = @order_clause = @scope_for_create = @arel = @loaded = nil
      @should_eager_load = @join_dependency = nil
      @records = []
      self
    end

    def to_sql
      @to_sql ||= klass.connection.to_sql(arel, @bind_values.dup)
    end

    def where_values_hash
      equalities = with_default_scope.where_values.grep(Arel::Nodes::Equality).find_all { |node|
        node.left.relation.name == table_name
      }

      Hash[equalities.map { |where| [where.left.name, where.right] }]
    end

    def scope_for_create
      @scope_for_create ||= where_values_hash.merge(create_with_value)
    end

    def eager_loading?
      @should_eager_load ||=
        @eager_load_values.any? ||
        @includes_values.any? && (joined_includes_values.any? || references_eager_loaded_tables?)
    end

    # Joins that are also marked for preloading. In which case we should just eager load them.
    # Note that this is a naive implementation because we could have strings and symbols which
    # represent the same association, but that aren't matched by this. Also, we could have
    # nested hashes which partially match, e.g. { :a => :b } & { :a => [:b, :c] }
    def joined_includes_values
      @includes_values & @joins_values
    end

    def ==(other)
      case other
      when Relation
        other.to_sql == to_sql
      when Array
        to_a == other
      end
    end

    def inspect
      to_a.inspect
    end

    def with_default_scope #:nodoc:
      if default_scoped? && default_scope = klass.send(:build_default_scope)
        default_scope = default_scope.merge(self)
        default_scope.default_scoped = false
        default_scope
      else
        self
      end
    end

    private

    def references_eager_loaded_tables?
      joined_tables = arel.join_sources.map do |join|
        if join.is_a?(Arel::Nodes::StringJoin)
          tables_in_string(join.left)
        else
          [join.left.table_name, join.left.table_alias]
        end
      end

      joined_tables += [table.name, table.table_alias]

      # always convert table names to downcase as in Oracle quoted table names are in uppercase
      joined_tables = joined_tables.flatten.compact.map { |t| t.downcase }.uniq

      (tables_in_string(to_sql) - joined_tables).any?
    end

    def tables_in_string(string)
      return [] if string.blank?
      # always convert table names to downcase as in Oracle quoted table names are in uppercase
      # ignore raw_sql_ that is used by Oracle adapter as alias for limit/offset subqueries
      string.scan(/([a-zA-Z_][.\w]+).?\./).flatten.map{ |s| s.downcase }.uniq - ['raw_sql_']
    end
  end
end
module ActiveRecord
  ###
  # This class encapsulates a Result returned from calling +exec_query+ on any
  # database connection adapter. For example:
  #
  #   x = ActiveRecord::Base.connection.exec_query('SELECT * FROM foo')
  #   x # => #<ActiveRecord::Result:0xdeadbeef>
  class Result
    include Enumerable

    attr_reader :columns, :rows

    def initialize(columns, rows)
      @columns   = columns
      @rows      = rows
      @hash_rows = nil
    end

    def each
      hash_rows.each { |row| yield row }
    end

    def to_hash
      hash_rows
    end

    private
    def hash_rows
      @hash_rows ||= @rows.map { |row|
        Hash[@columns.zip(row)]
      }
    end
  end
end
require 'active_support/concern'

module ActiveRecord
  module Sanitization
    extend ActiveSupport::Concern

    module ClassMethods
      def quote_value(value, column = nil) #:nodoc:
        connection.quote(value,column)
      end

      # Used to sanitize objects before they're used in an SQL SELECT statement. Delegates to <tt>connection.quote</tt>.
      def sanitize(object) #:nodoc:
        connection.quote(object)
      end

      protected

      # Accepts an array, hash, or string of SQL conditions and sanitizes
      # them into a valid SQL fragment for a WHERE clause.
      #   ["name='%s' and group_id='%s'", "foo'bar", 4]  returns  "name='foo''bar' and group_id='4'"
      #   { :name => "foo'bar", :group_id => 4 }  returns "name='foo''bar' and group_id='4'"
      #   "name='foo''bar' and group_id='4'" returns "name='foo''bar' and group_id='4'"
      def sanitize_sql_for_conditions(condition, table_name = self.table_name)
        return nil if condition.blank?

        case condition
        when Array; sanitize_sql_array(condition)
        when Hash;  sanitize_sql_hash_for_conditions(condition, table_name)
        else        condition
        end
      end
      alias_method :sanitize_sql, :sanitize_sql_for_conditions

      # Accepts an array, hash, or string of SQL conditions and sanitizes
      # them into a valid SQL fragment for a SET clause.
      #   { :name => nil, :group_id => 4 }  returns "name = NULL , group_id='4'"
      def sanitize_sql_for_assignment(assignments)
        case assignments
          when Array; sanitize_sql_array(assignments)
          when Hash;  sanitize_sql_hash_for_assignment(assignments)
          else        assignments
        end
      end

      # Accepts a hash of SQL conditions and replaces those attributes
      # that correspond to a +composed_of+ relationship with their expanded
      # aggregate attribute values.
      # Given:
      #     class Person < ActiveRecord::Base
      #       composed_of :address, :class_name => "Address",
      #         :mapping => [%w(address_street street), %w(address_city city)]
      #     end
      # Then:
      #     { :address => Address.new("813 abc st.", "chicago") }
      #       # => { :address_street => "813 abc st.", :address_city => "chicago" }
      def expand_hash_conditions_for_aggregates(attrs)
        expanded_attrs = {}
        attrs.each do |attr, value|
          unless (aggregation = reflect_on_aggregation(attr.to_sym)).nil?
            mapping = aggregate_mapping(aggregation)
            mapping.each do |field_attr, aggregate_attr|
              if mapping.size == 1 && !value.respond_to?(aggregate_attr)
                expanded_attrs[field_attr] = value
              else
                expanded_attrs[field_attr] = value.send(aggregate_attr)
              end
            end
          else
            expanded_attrs[attr] = value
          end
        end
        expanded_attrs
      end

      # Sanitizes a hash of attribute/value pairs into SQL conditions for a WHERE clause.
      #   { :name => "foo'bar", :group_id => 4 }
      #     # => "name='foo''bar' and group_id= 4"
      #   { :status => nil, :group_id => [1,2,3] }
      #     # => "status IS NULL and group_id IN (1,2,3)"
      #   { :age => 13..18 }
      #     # => "age BETWEEN 13 AND 18"
      #   { 'other_records.id' => 7 }
      #     # => "`other_records`.`id` = 7"
      #   { :other_records => { :id => 7 } }
      #     # => "`other_records`.`id` = 7"
      # And for value objects on a composed_of relationship:
      #   { :address => Address.new("123 abc st.", "chicago") }
      #     # => "address_street='123 abc st.' and address_city='chicago'"
      def sanitize_sql_hash_for_conditions(attrs, default_table_name = self.table_name)
        attrs = expand_hash_conditions_for_aggregates(attrs)

        table = Arel::Table.new(table_name).alias(default_table_name)
        PredicateBuilder.build_from_hash(arel_engine, attrs, table).map { |b|
          connection.visitor.accept b
        }.join(' AND ')
      end
      alias_method :sanitize_sql_hash, :sanitize_sql_hash_for_conditions

      # Sanitizes a hash of attribute/value pairs into SQL conditions for a SET clause.
      #   { :status => nil, :group_id => 1 }
      #     # => "status = NULL , group_id = 1"
      def sanitize_sql_hash_for_assignment(attrs)
        attrs.map do |attr, value|
          "#{connection.quote_column_name(attr)} = #{quote_bound_value(value)}"
        end.join(', ')
      end

      # Accepts an array of conditions. The array has each value
      # sanitized and interpolated into the SQL statement.
      #   ["name='%s' and group_id='%s'", "foo'bar", 4]  returns  "name='foo''bar' and group_id='4'"
      def sanitize_sql_array(ary)
        statement, *values = ary
        if values.first.is_a?(Hash) && statement =~ /:\w+/
          replace_named_bind_variables(statement, values.first)
        elsif statement.include?('?')
          replace_bind_variables(statement, values)
        elsif statement.blank?
          statement
        else
          statement % values.collect { |value| connection.quote_string(value.to_s) }
        end
      end

      alias_method :sanitize_conditions, :sanitize_sql

      def replace_bind_variables(statement, values) #:nodoc:
        raise_if_bind_arity_mismatch(statement, statement.count('?'), values.size)
        bound = values.dup
        c = connection
        statement.gsub('?') { quote_bound_value(bound.shift, c) }
      end

      def replace_named_bind_variables(statement, bind_vars) #:nodoc:
        statement.gsub(/(:?):([a-zA-Z]\w*)/) do
          if $1 == ':' # skip postgresql casts
            $& # return the whole match
          elsif bind_vars.include?(match = $2.to_sym)
            quote_bound_value(bind_vars[match])
          else
            raise PreparedStatementInvalid, "missing value for :#{match} in #{statement}"
          end
        end
      end

      def expand_range_bind_variables(bind_vars) #:nodoc:
        expanded = []

        bind_vars.each do |var|
          next if var.is_a?(Hash)

          if var.is_a?(Range)
            expanded << var.first
            expanded << var.last
          else
            expanded << var
          end
        end

        expanded
      end

      def quote_bound_value(value, c = connection) #:nodoc:
        if value.respond_to?(:map) && !value.acts_like?(:string)
          if value.respond_to?(:empty?) && value.empty?
            c.quote(nil)
          else
            value.map { |v| c.quote(v) }.join(',')
          end
        else
          c.quote(value)
        end
      end

      def raise_if_bind_arity_mismatch(statement, expected, provided) #:nodoc:
        unless expected == provided
          raise PreparedStatementInvalid, "wrong number of bind variables (#{provided} for #{expected}) in: #{statement}"
        end
      end
    end

    # TODO: Deprecate this
    def quoted_id #:nodoc:
      quote_value(id, column_for_attribute(self.class.primary_key))
    end

    private

    # Quote strings appropriately for SQL statements.
    def quote_value(value, column = nil)
      self.class.connection.quote(value, column)
    end
  end
end
require 'active_support/core_ext/object/blank'

module ActiveRecord
  # = Active Record Schema
  #
  # Allows programmers to programmatically define a schema in a portable
  # DSL. This means you can define tables, indexes, etc. without using SQL
  # directly, so your applications can more easily support multiple
  # databases.
  #
  # Usage:
  #
  #   ActiveRecord::Schema.define do
  #     create_table :authors do |t|
  #       t.string :name, :null => false
  #     end
  #
  #     add_index :authors, :name, :unique
  #
  #     create_table :posts do |t|
  #       t.integer :author_id, :null => false
  #       t.string :subject
  #       t.text :body
  #       t.boolean :private, :default => false
  #     end
  #
  #     add_index :posts, :author_id
  #   end
  #
  # ActiveRecord::Schema is only supported by database adapters that also
  # support migrations, the two features being very similar.
  class Schema < Migration
    def migrations_paths
      ActiveRecord::Migrator.migrations_paths
    end

    # Eval the given block. All methods available to the current connection
    # adapter are available within the block, so you can easily use the
    # database definition DSL to build up your schema (+create_table+,
    # +add_index+, etc.).
    #
    # The +info+ hash is optional, and if given is used to define metadata
    # about the current schema (currently, only the schema's version):
    #
    #   ActiveRecord::Schema.define(:version => 20380119000001) do
    #     ...
    #   end
    def self.define(info={}, &block)
      schema = new
      schema.instance_eval(&block)

      unless info[:version].blank?
        initialize_schema_migrations_table
        assume_migrated_upto_version(info[:version], schema.migrations_paths)
      end
    end
  end
end
require 'stringio'
require 'active_support/core_ext/big_decimal'

module ActiveRecord
  # = Active Record Schema Dumper
  #
  # This class is used to dump the database schema for some connection to some
  # output format (i.e., ActiveRecord::Schema).
  class SchemaDumper #:nodoc:
    private_class_method :new

    ##
    # :singleton-method:
    # A list of tables which should not be dumped to the schema.
    # Acceptable values are strings as well as regexp.
    # This setting is only used if ActiveRecord::Base.schema_format == :ruby
    cattr_accessor :ignore_tables
    @@ignore_tables = []

    def self.dump(connection=ActiveRecord::Base.connection, stream=STDOUT)
      new(connection).dump(stream)
      stream
    end

    def dump(stream)
      header(stream)
      tables(stream)
      trailer(stream)
      stream
    end

    private

      def initialize(connection)
        @connection = connection
        @types = @connection.native_database_types
        @version = Migrator::current_version rescue nil
      end

      def header(stream)
        define_params = @version ? ":version => #{@version}" : ""

        if stream.respond_to?(:external_encoding) && stream.external_encoding
          stream.puts "# encoding: #{stream.external_encoding.name}"
        end

        stream.puts <<HEADER
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(#{define_params}) do

HEADER
      end

      def trailer(stream)
        stream.puts "end"
      end

      def tables(stream)
        @connection.tables.sort.each do |tbl|
          next if ['schema_migrations', ignore_tables].flatten.any? do |ignored|
            case ignored
            when String; remove_prefix_and_suffix(tbl) == ignored
            when Regexp; remove_prefix_and_suffix(tbl) =~ ignored
            else
              raise StandardError, 'ActiveRecord::SchemaDumper.ignore_tables accepts an array of String and / or Regexp values.'
            end
          end
          table(tbl, stream)
        end
      end

      def table(table, stream)
        columns = @connection.columns(table)
        begin
          tbl = StringIO.new

          # first dump primary key column
          if @connection.respond_to?(:pk_and_sequence_for)
            pk, _ = @connection.pk_and_sequence_for(table)
          elsif @connection.respond_to?(:primary_key)
            pk = @connection.primary_key(table)
          end

          tbl.print "  create_table #{remove_prefix_and_suffix(table).inspect}"
          if columns.detect { |c| c.name == pk }
            if pk != 'id'
              tbl.print %Q(, :primary_key => "#{pk}")
            end
          else
            tbl.print ", :id => false"
          end
          tbl.print ", :force => true"
          tbl.puts " do |t|"

          # then dump all non-primary key columns
          column_specs = columns.map do |column|
            raise StandardError, "Unknown type '#{column.sql_type}' for column '#{column.name}'" if @types[column.type].nil?
            next if column.name == pk
            spec = {}
            spec[:name]      = column.name.inspect

            # AR has an optimization which handles zero-scale decimals as integers. This
            # code ensures that the dumper still dumps the column as a decimal.
            spec[:type]      = if column.type == :integer && [/^numeric/, /^decimal/].any? { |e| e.match(column.sql_type) }
                                 'decimal'
                               else
                                 column.type.to_s
                               end
            spec[:limit]     = column.limit.inspect if column.limit != @types[column.type][:limit] && spec[:type] != 'decimal'
            spec[:precision] = column.precision.inspect if column.precision
            spec[:scale]     = column.scale.inspect if column.scale
            spec[:null]      = 'false' unless column.null
            spec[:default]   = default_string(column.default) if column.has_default?
            (spec.keys - [:name, :type]).each{ |k| spec[k].insert(0, "#{k.inspect} => ")}
            spec
          end.compact

          # find all migration keys used in this table
          keys = [:name, :limit, :precision, :scale, :default, :null] & column_specs.map{ |k| k.keys }.flatten

          # figure out the lengths for each column based on above keys
          lengths = keys.map{ |key| column_specs.map{ |spec| spec[key] ? spec[key].length + 2 : 0 }.max }

          # the string we're going to sprintf our values against, with standardized column widths
          format_string = lengths.map{ |len| "%-#{len}s" }

          # find the max length for the 'type' column, which is special
          type_length = column_specs.map{ |column| column[:type].length }.max

          # add column type definition to our format string
          format_string.unshift "    t.%-#{type_length}s "

          format_string *= ''

          column_specs.each do |colspec|
            values = keys.zip(lengths).map{ |key, len| colspec.key?(key) ? colspec[key] + ", " : " " * len }
            values.unshift colspec[:type]
            tbl.print((format_string % values).gsub(/,\s*$/, ''))
            tbl.puts
          end

          tbl.puts "  end"
          tbl.puts

          indexes(table, tbl)

          tbl.rewind
          stream.print tbl.read
        rescue => e
          stream.puts "# Could not dump table #{table.inspect} because of following #{e.class}"
          stream.puts "#   #{e.message}"
          stream.puts
        end

        stream
      end

      def default_string(value)
        case value
        when BigDecimal
          value.to_s
        when Date, DateTime, Time
          "'" + value.to_s(:db) + "'"
        else
          value.inspect
        end
      end

      def indexes(table, stream)
        if (indexes = @connection.indexes(table)).any?
          add_index_statements = indexes.map do |index|
            statement_parts = [
              ('add_index ' + remove_prefix_and_suffix(index.table).inspect),
              index.columns.inspect,
              (':name => ' + index.name.inspect),
            ]
            statement_parts << ':unique => true' if index.unique

            index_lengths = (index.lengths || []).compact
            statement_parts << (':length => ' + Hash[index.columns.zip(index.lengths)].inspect) unless index_lengths.empty?

            index_orders = (index.orders || {})
            statement_parts << (':order => ' + index.orders.inspect) unless index_orders.empty?

            '  ' + statement_parts.join(', ')
          end

          stream.puts add_index_statements.sort.join("\n")
          stream.puts
        end
      end

      def remove_prefix_and_suffix(table)
        table.gsub(/^(#{ActiveRecord::Base.table_name_prefix})(.+)(#{ActiveRecord::Base.table_name_suffix})$/,  "\\2")
      end
  end
end
require 'active_support/concern'

module ActiveRecord
  module Scoping
    module Default
      extend ActiveSupport::Concern

      included do
        # Stores the default scope for the class
        class_attribute :default_scopes, :instance_writer => false
        self.default_scopes = []
      end

      module ClassMethods
        # Returns a scope for the model without the default_scope.
        #
        #   class Post < ActiveRecord::Base
        #     def self.default_scope
        #       where :published => true
        #     end
        #   end
        #
        #   Post.all          # Fires "SELECT * FROM posts WHERE published = true"
        #   Post.unscoped.all # Fires "SELECT * FROM posts"
        #
        # This method also accepts a block. All queries inside the block will
        # not use the default_scope:
        #
        #   Post.unscoped {
        #     Post.limit(10) # Fires "SELECT * FROM posts LIMIT 10"
        #   }
        #
        # It is recommended to use the block form of unscoped because chaining
        # unscoped with <tt>scope</tt> does not work.  Assuming that
        # <tt>published</tt> is a <tt>scope</tt>, the following two statements
        # are equal: the default_scope is applied on both.
        #
        #   Post.unscoped.published
        #   Post.published
        def unscoped #:nodoc:
          block_given? ? relation.scoping { yield } : relation
        end

        def before_remove_const #:nodoc:
          self.current_scope = nil
        end

        protected

        # Use this macro in your model to set a default scope for all operations on
        # the model.
        #
        #   class Article < ActiveRecord::Base
        #     default_scope where(:published => true)
        #   end
        #
        #   Article.all # => SELECT * FROM articles WHERE published = true
        #
        # The <tt>default_scope</tt> is also applied while creating/building a record. It is not
        # applied while updating a record.
        #
        #   Article.new.published    # => true
        #   Article.create.published # => true
        #
        # You can also use <tt>default_scope</tt> with a block, in order to have it lazily evaluated:
        #
        #   class Article < ActiveRecord::Base
        #     default_scope { where(:published_at => Time.now - 1.week) }
        #   end
        #
        # (You can also pass any object which responds to <tt>call</tt> to the <tt>default_scope</tt>
        # macro, and it will be called when building the default scope.)
        #
        # If you use multiple <tt>default_scope</tt> declarations in your model then they will
        # be merged together:
        #
        #   class Article < ActiveRecord::Base
        #     default_scope where(:published => true)
        #     default_scope where(:rating => 'G')
        #   end
        #
        #   Article.all # => SELECT * FROM articles WHERE published = true AND rating = 'G'
        #
        # This is also the case with inheritance and module includes where the parent or module
        # defines a <tt>default_scope</tt> and the child or including class defines a second one.
        #
        # If you need to do more complex things with a default scope, you can alternatively
        # define it as a class method:
        #
        #   class Article < ActiveRecord::Base
        #     def self.default_scope
        #       # Should return a scope, you can call 'super' here etc.
        #     end
        #   end
        def default_scope(scope = {})
          scope = Proc.new if block_given?
          self.default_scopes = default_scopes + [scope]
        end

        def build_default_scope #:nodoc:
          if method(:default_scope).owner != ActiveRecord::Scoping::Default::ClassMethods
            evaluate_default_scope { default_scope }
          elsif default_scopes.any?
            evaluate_default_scope do
              default_scopes.inject(relation) do |default_scope, scope|
                if scope.is_a?(Hash)
                  default_scope.apply_finder_options(scope)
                elsif !scope.is_a?(Relation) && scope.respond_to?(:call)
                  default_scope.merge(scope.call)
                else
                  default_scope.merge(scope)
                end
              end
            end
          end
        end

        def ignore_default_scope? #:nodoc:
          Thread.current["#{self}_ignore_default_scope"]
        end

        def ignore_default_scope=(ignore) #:nodoc:
          Thread.current["#{self}_ignore_default_scope"] = ignore
        end

        # The ignore_default_scope flag is used to prevent an infinite recursion situation where
        # a default scope references a scope which has a default scope which references a scope...
        def evaluate_default_scope
          return if ignore_default_scope?

          begin
            self.ignore_default_scope = true
            yield
          ensure
            self.ignore_default_scope = false
          end
        end

      end
    end
  end
end
require 'active_support/core_ext/array'
require 'active_support/core_ext/hash/except'
require 'active_support/core_ext/kernel/singleton_class'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/class/attribute'

module ActiveRecord
  # = Active Record Named \Scopes
  module Scoping
    module Named
      extend ActiveSupport::Concern

      module ClassMethods
        # Returns an anonymous \scope.
        #
        #   posts = Post.scoped
        #   posts.size # Fires "select count(*) from  posts" and returns the count
        #   posts.each {|p| puts p.name } # Fires "select * from posts" and loads post objects
        #
        #   fruits = Fruit.scoped
        #   fruits = fruits.where(:color => 'red') if options[:red_only]
        #   fruits = fruits.limit(10) if limited?
        #
        # Anonymous \scopes tend to be useful when procedurally generating complex
        # queries, where passing intermediate values (\scopes) around as first-class
        # objects is convenient.
        #
        # You can define a \scope that applies to all finders using
        # ActiveRecord::Base.default_scope.
        def scoped(options = nil)
          if options
            scoped.apply_finder_options(options)
          else
            if current_scope
              current_scope.clone
            else
              scope = relation
              scope.default_scoped = true
              scope
            end
          end
        end

        ##
        # Collects attributes from scopes that should be applied when creating
        # an AR instance for the particular class this is called on.
        def scope_attributes # :nodoc:
          if current_scope
            current_scope.scope_for_create
          else
            scope = relation
            scope.default_scoped = true
            scope.scope_for_create
          end
        end

        ##
        # Are there default attributes associated with this scope?
        def scope_attributes? # :nodoc:
          current_scope || default_scopes.any?
        end

        # Adds a class method for retrieving and querying objects. A \scope represents a narrowing of a database query,
        # such as <tt>where(:color => :red).select('shirts.*').includes(:washing_instructions)</tt>.
        #
        #   class Shirt < ActiveRecord::Base
        #     scope :red, where(:color => 'red')
        #     scope :dry_clean_only, joins(:washing_instructions).where('washing_instructions.dry_clean_only = ?', true)
        #   end
        #
        # The above calls to <tt>scope</tt> define class methods Shirt.red and Shirt.dry_clean_only. Shirt.red,
        # in effect, represents the query <tt>Shirt.where(:color => 'red')</tt>.
        #
        # Note that this is simply 'syntactic sugar' for defining an actual class method:
        #
        #   class Shirt < ActiveRecord::Base
        #     def self.red
        #       where(:color => 'red')
        #     end
        #   end
        #
        # Unlike <tt>Shirt.find(...)</tt>, however, the object returned by Shirt.red is not an Array; it
        # resembles the association object constructed by a <tt>has_many</tt> declaration. For instance,
        # you can invoke <tt>Shirt.red.first</tt>, <tt>Shirt.red.count</tt>, <tt>Shirt.red.where(:size => 'small')</tt>.
        # Also, just as with the association objects, named \scopes act like an Array, implementing Enumerable;
        # <tt>Shirt.red.each(&block)</tt>, <tt>Shirt.red.first</tt>, and <tt>Shirt.red.inject(memo, &block)</tt>
        # all behave as if Shirt.red really was an Array.
        #
        # These named \scopes are composable. For instance, <tt>Shirt.red.dry_clean_only</tt> will produce
        # all shirts that are both red and dry clean only.
        # Nested finds and calculations also work with these compositions: <tt>Shirt.red.dry_clean_only.count</tt>
        # returns the number of garments for which these criteria obtain. Similarly with
        # <tt>Shirt.red.dry_clean_only.average(:thread_count)</tt>.
        #
        # All \scopes are available as class methods on the ActiveRecord::Base descendant upon which
        # the \scopes were defined. But they are also available to <tt>has_many</tt> associations. If,
        #
        #   class Person < ActiveRecord::Base
        #     has_many :shirts
        #   end
        #
        # then <tt>elton.shirts.red.dry_clean_only</tt> will return all of Elton's red, dry clean
        # only shirts.
        #
        # Named \scopes can also be procedural:
        #
        #   class Shirt < ActiveRecord::Base
        #     scope :colored, lambda { |color| where(:color => color) }
        #   end
        #
        # In this example, <tt>Shirt.colored('puce')</tt> finds all puce shirts.
        #
        # On Ruby 1.9 you can use the 'stabby lambda' syntax:
        #
        #   scope :colored, ->(color) { where(:color => color) }
        #
        # Note that scopes defined with \scope will be evaluated when they are defined, rather than
        # when they are used. For example, the following would be incorrect:
        #
        #   class Post < ActiveRecord::Base
        #     scope :recent, where('published_at >= ?', Time.current - 1.week)
        #   end
        #
        # The example above would be 'frozen' to the <tt>Time.current</tt> value when the <tt>Post</tt>
        # class was defined, and so the resultant SQL query would always be the same. The correct
        # way to do this would be via a lambda, which will re-evaluate the scope each time
        # it is called:
        #
        #   class Post < ActiveRecord::Base
        #     scope :recent, lambda { where('published_at >= ?', Time.current - 1.week) }
        #   end
        #
        # Named \scopes can also have extensions, just as with <tt>has_many</tt> declarations:
        #
        #   class Shirt < ActiveRecord::Base
        #     scope :red, where(:color => 'red') do
        #       def dom_id
        #         'red_shirts'
        #       end
        #     end
        #   end
        #
        # Scopes can also be used while creating/building a record.
        #
        #   class Article < ActiveRecord::Base
        #     scope :published, where(:published => true)
        #   end
        #
        #   Article.published.new.published    # => true
        #   Article.published.create.published # => true
        #
        # Class methods on your model are automatically available
        # on scopes. Assuming the following setup:
        #
        #   class Article < ActiveRecord::Base
        #     scope :published, where(:published => true)
        #     scope :featured, where(:featured => true)
        #
        #     def self.latest_article
        #       order('published_at desc').first
        #     end
        #
        #     def self.titles
        #       map(&:title)
        #     end
        #
        #   end
        #
        # We are able to call the methods like this:
        #
        #   Article.published.featured.latest_article
        #   Article.featured.titles

        def scope(name, scope_options = {})
          name = name.to_sym
          valid_scope_name?(name)
          extension = Module.new(&Proc.new) if block_given?

          scope_proc = lambda do |*args|
            options = scope_options.respond_to?(:call) ? unscoped { scope_options.call(*args) } : scope_options
            options = scoped.apply_finder_options(options) if options.is_a?(Hash)

            relation = scoped.merge(options)

            extension ? relation.extending(extension) : relation
          end

          singleton_class.send(:redefine_method, name, &scope_proc)
        end

      protected

        def valid_scope_name?(name)
          if logger && respond_to?(name, true)
            logger.warn "Creating scope :#{name}. " \
                        "Overwriting existing method #{self.name}.#{name}."
          end
        end
      end
    end
  end
end
require 'active_support/concern'

module ActiveRecord
  module Scoping
    extend ActiveSupport::Concern

    included do
      include Default
      include Named
    end

    module ClassMethods
      # with_scope lets you apply options to inner block incrementally. It takes a hash and the keys must be
      # <tt>:find</tt> or <tt>:create</tt>. <tt>:find</tt> parameter is <tt>Relation</tt> while
      # <tt>:create</tt> parameters are an attributes hash.
      #
      #   class Article < ActiveRecord::Base
      #     def self.create_with_scope
      #       with_scope(:find => where(:blog_id => 1), :create => { :blog_id => 1 }) do
      #         find(1) # => SELECT * from articles WHERE blog_id = 1 AND id = 1
      #         a = create(1)
      #         a.blog_id # => 1
      #       end
      #     end
      #   end
      #
      # In nested scopings, all previous parameters are overwritten by the innermost rule, with the exception of
      # <tt>where</tt>, <tt>includes</tt>, and <tt>joins</tt> operations in <tt>Relation</tt>, which are merged.
      #
      # <tt>joins</tt> operations are uniqued so multiple scopes can join in the same table without table aliasing
      # problems. If you need to join multiple tables, but still want one of the tables to be uniqued, use the
      # array of strings format for your joins.
      #
      #   class Article < ActiveRecord::Base
      #     def self.find_with_scope
      #       with_scope(:find => where(:blog_id => 1).limit(1), :create => { :blog_id => 1 }) do
      #         with_scope(:find => limit(10)) do
      #           all # => SELECT * from articles WHERE blog_id = 1 LIMIT 10
      #         end
      #         with_scope(:find => where(:author_id => 3)) do
      #           all # => SELECT * from articles WHERE blog_id = 1 AND author_id = 3 LIMIT 1
      #         end
      #       end
      #     end
      #   end
      #
      # You can ignore any previous scopings by using the <tt>with_exclusive_scope</tt> method.
      #
      #   class Article < ActiveRecord::Base
      #     def self.find_with_exclusive_scope
      #       with_scope(:find => where(:blog_id => 1).limit(1)) do
      #         with_exclusive_scope(:find => limit(10)) do
      #           all # => SELECT * from articles LIMIT 10
      #         end
      #       end
      #     end
      #   end
      #
      # *Note*: the +:find+ scope also has effect on update and deletion methods, like +update_all+ and +delete_all+.
      def with_scope(scope = {}, action = :merge, &block)
        # If another Active Record class has been passed in, get its current scope
        scope = scope.current_scope if !scope.is_a?(Relation) && scope.respond_to?(:current_scope)

        previous_scope = self.current_scope

        if scope.is_a?(Hash)
          # Dup first and second level of hash (method and params).
          scope = scope.dup
          scope.each do |method, params|
            scope[method] = params.dup unless params == true
          end

          scope.assert_valid_keys([ :find, :create ])
          relation = construct_finder_arel(scope[:find] || {})
          relation.default_scoped = true unless action == :overwrite

          if previous_scope && previous_scope.create_with_value && scope[:create]
            scope_for_create = if action == :merge
              previous_scope.create_with_value.merge(scope[:create])
            else
              scope[:create]
            end

            relation = relation.create_with(scope_for_create)
          else
            scope_for_create = scope[:create]
            scope_for_create ||= previous_scope.create_with_value if previous_scope
            relation = relation.create_with(scope_for_create) if scope_for_create
          end

          scope = relation
        end

        scope = previous_scope.merge(scope) if previous_scope && action == :merge

        self.current_scope = scope
        begin
          yield
        ensure
          self.current_scope = previous_scope
        end
      end

      protected

      # Works like with_scope, but discards any nested properties.
      def with_exclusive_scope(method_scoping = {}, &block)
        if method_scoping.values.any? { |e| e.is_a?(ActiveRecord::Relation) }
          raise ArgumentError, <<-MSG
  New finder API can not be used with_exclusive_scope. You can either call unscoped to get an anonymous scope not bound to the default_scope:

  User.unscoped.where(:active => true)

  Or call unscoped with a block:

  User.unscoped do
  User.where(:active => true).all
  end

  MSG
        end
        with_scope(method_scoping, :overwrite, &block)
      end

      def current_scope #:nodoc:
        Thread.current["#{self}_current_scope"]
      end

      def current_scope=(scope) #:nodoc:
        Thread.current["#{self}_current_scope"] = scope
      end

      private

      def construct_finder_arel(options = {}, scope = nil)
        relation = options.is_a?(Hash) ? unscoped.apply_finder_options(options) : options
        relation = scope.merge(relation) if scope
        relation
      end

    end

    def populate_with_current_scope_attributes
      return unless self.class.scope_attributes?

      self.class.scope_attributes.each do |att,value|
        send("#{att}=", value) if respond_to?("#{att}=")
      end
    end

  end
end
module ActiveRecord #:nodoc:
  # = Active Record Serialization
  module Serialization
    extend ActiveSupport::Concern
    include ActiveModel::Serializers::JSON

    def serializable_hash(options = nil)
      options = options.try(:clone) || {}

      options[:except] = Array.wrap(options[:except]).map { |n| n.to_s }
      options[:except] |= Array.wrap(self.class.inheritance_column)

      super(options)
    end
  end
end

require 'active_record/serializers/xml_serializer'
require 'active_support/core_ext/array/wrap'
require 'active_support/core_ext/hash/conversions'

module ActiveRecord #:nodoc:
  module Serialization
    include ActiveModel::Serializers::Xml

    # Builds an XML document to represent the model. Some configuration is
    # available through +options+. However more complicated cases should
    # override ActiveRecord::Base#to_xml.
    #
    # By default the generated XML document will include the processing
    # instruction and all the object's attributes. For example:
    #
    #   <?xml version="1.0" encoding="UTF-8"?>
    #   <topic>
    #     <title>The First Topic</title>
    #     <author-name>David</author-name>
    #     <id type="integer">1</id>
    #     <approved type="boolean">false</approved>
    #     <replies-count type="integer">0</replies-count>
    #     <bonus-time type="datetime">2000-01-01T08:28:00+12:00</bonus-time>
    #     <written-on type="datetime">2003-07-16T09:28:00+1200</written-on>
    #     <content>Have a nice day</content>
    #     <author-email-address>david@loudthinking.com</author-email-address>
    #     <parent-id></parent-id>
    #     <last-read type="date">2004-04-15</last-read>
    #   </topic>
    #
    # This behavior can be controlled with <tt>:only</tt>, <tt>:except</tt>,
    # <tt>:skip_instruct</tt>, <tt>:skip_types</tt>, <tt>:dasherize</tt> and <tt>:camelize</tt> .
    # The <tt>:only</tt> and <tt>:except</tt> options are the same as for the
    # +attributes+ method. The default is to dasherize all column names, but you
    # can disable this setting <tt>:dasherize</tt> to +false+. Setting <tt>:camelize</tt>
    # to +true+ will camelize all column names - this also overrides <tt>:dasherize</tt>.
    # To not have the column type included in the XML output set <tt>:skip_types</tt> to +true+.
    #
    # For instance:
    #
    #   topic.to_xml(:skip_instruct => true, :except => [ :id, :bonus_time, :written_on, :replies_count ])
    #
    #   <topic>
    #     <title>The First Topic</title>
    #     <author-name>David</author-name>
    #     <approved type="boolean">false</approved>
    #     <content>Have a nice day</content>
    #     <author-email-address>david@loudthinking.com</author-email-address>
    #     <parent-id></parent-id>
    #     <last-read type="date">2004-04-15</last-read>
    #   </topic>
    #
    # To include first level associations use <tt>:include</tt>:
    #
    #   firm.to_xml :include => [ :account, :clients ]
    #
    #   <?xml version="1.0" encoding="UTF-8"?>
    #   <firm>
    #     <id type="integer">1</id>
    #     <rating type="integer">1</rating>
    #     <name>37signals</name>
    #     <clients type="array">
    #       <client>
    #         <rating type="integer">1</rating>
    #         <name>Summit</name>
    #       </client>
    #       <client>
    #         <rating type="integer">1</rating>
    #         <name>Microsoft</name>
    #       </client>
    #     </clients>
    #     <account>
    #       <id type="integer">1</id>
    #       <credit-limit type="integer">50</credit-limit>
    #     </account>
    #   </firm>
    #
    # Additionally, the record being serialized will be passed to a Proc's second
    # parameter. This allows for ad hoc additions to the resultant document that
    # incorporate the context of the record being serialized. And by leveraging the
    # closure created by a Proc, to_xml can be used to add elements that normally fall
    # outside of the scope of the model -- for example, generating and appending URLs
    # associated with models.
    #
    #   proc = Proc.new { |options, record| options[:builder].tag!('name-reverse', record.name.reverse) }
    #   firm.to_xml :procs => [ proc ]
    #
    #   <firm>
    #     # ... normal attributes as shown above ...
    #     <name-reverse>slangis73</name-reverse>
    #   </firm>
    #
    # To include deeper levels of associations pass a hash like this:
    #
    #   firm.to_xml :include => {:account => {}, :clients => {:include => :address}}
    #   <?xml version="1.0" encoding="UTF-8"?>
    #   <firm>
    #     <id type="integer">1</id>
    #     <rating type="integer">1</rating>
    #     <name>37signals</name>
    #     <clients type="array">
    #       <client>
    #         <rating type="integer">1</rating>
    #         <name>Summit</name>
    #         <address>
    #           ...
    #         </address>
    #       </client>
    #       <client>
    #         <rating type="integer">1</rating>
    #         <name>Microsoft</name>
    #         <address>
    #           ...
    #         </address>
    #       </client>
    #     </clients>
    #     <account>
    #       <id type="integer">1</id>
    #       <credit-limit type="integer">50</credit-limit>
    #     </account>
    #   </firm>
    #
    # To include any methods on the model being called use <tt>:methods</tt>:
    #
    #   firm.to_xml :methods => [ :calculated_earnings, :real_earnings ]
    #
    #   <firm>
    #     # ... normal attributes as shown above ...
    #     <calculated-earnings>100000000000000000</calculated-earnings>
    #     <real-earnings>5</real-earnings>
    #   </firm>
    #
    # To call any additional Procs use <tt>:procs</tt>. The Procs are passed a
    # modified version of the options hash that was given to +to_xml+:
    #
    #   proc = Proc.new { |options| options[:builder].tag!('abc', 'def') }
    #   firm.to_xml :procs => [ proc ]
    #
    #   <firm>
    #     # ... normal attributes as shown above ...
    #     <abc>def</abc>
    #   </firm>
    #
    # Alternatively, you can yield the builder object as part of the +to_xml+ call:
    #
    #   firm.to_xml do |xml|
    #     xml.creator do
    #       xml.first_name "David"
    #       xml.last_name "Heinemeier Hansson"
    #     end
    #   end
    #
    #   <firm>
    #     # ... normal attributes as shown above ...
    #     <creator>
    #       <first_name>David</first_name>
    #       <last_name>Heinemeier Hansson</last_name>
    #     </creator>
    #   </firm>
    #
    # As noted above, you may override +to_xml+ in your ActiveRecord::Base
    # subclasses to have complete control about what's generated. The general
    # form of doing this is:
    #
    #   class IHaveMyOwnXML < ActiveRecord::Base
    #     def to_xml(options = {})
    #       require 'builder'
    #       options[:indent] ||= 2
    #       xml = options[:builder] ||= ::Builder::XmlMarkup.new(:indent => options[:indent])
    #       xml.instruct! unless options[:skip_instruct]
    #       xml.level_one do
    #         xml.tag!(:second_level, 'content')
    #       end
    #     end
    #   end
    def to_xml(options = {}, &block)
      XmlSerializer.new(self, options).serialize(&block)
    end
  end

  class XmlSerializer < ActiveModel::Serializers::Xml::Serializer #:nodoc:
    def initialize(*args)
      super
      options[:except] = Array.wrap(options[:except]) | Array.wrap(@serializable.class.inheritance_column)
    end

    class Attribute < ActiveModel::Serializers::Xml::Serializer::Attribute #:nodoc:
      def compute_type
        klass = @serializable.class
        type = if klass.serialized_attributes.key?(name)
                 super
               elsif klass.columns_hash.key?(name)
                 klass.columns_hash[name].type
               else
                 NilClass
               end

        { :text => :string,
          :time => :datetime }[type] || type
      end
      protected :compute_type
    end
  end
end
require 'action_dispatch/middleware/session/abstract_store'

module ActiveRecord
  # = Active Record Session Store
  #
  # A session store backed by an Active Record class. A default class is
  # provided, but any object duck-typing to an Active Record Session class
  # with text +session_id+ and +data+ attributes is sufficient.
  #
  # The default assumes a +sessions+ tables with columns:
  #   +id+ (numeric primary key),
  #   +session_id+ (text, or longtext if your session data exceeds 65K), and
  #   +data+ (text or longtext; careful if your session data exceeds 65KB).
  #
  # The +session_id+ column should always be indexed for speedy lookups.
  # Session data is marshaled to the +data+ column in Base64 format.
  # If the data you write is larger than the column's size limit,
  # ActionController::SessionOverflowError will be raised.
  #
  # You may configure the table name, primary key, and data column.
  # For example, at the end of <tt>config/application.rb</tt>:
  #
  #   ActiveRecord::SessionStore::Session.table_name = 'legacy_session_table'
  #   ActiveRecord::SessionStore::Session.primary_key = 'session_id'
  #   ActiveRecord::SessionStore::Session.data_column_name = 'legacy_session_data'
  #
  # Note that setting the primary key to the +session_id+ frees you from
  # having a separate +id+ column if you don't want it. However, you must
  # set <tt>session.model.id = session.session_id</tt> by hand!  A before filter
  # on ApplicationController is a good place.
  #
  # Since the default class is a simple Active Record, you get timestamps
  # for free if you add +created_at+ and +updated_at+ datetime columns to
  # the +sessions+ table, making periodic session expiration a snap.
  #
  # You may provide your own session class implementation, whether a
  # feature-packed Active Record or a bare-metal high-performance SQL
  # store, by setting
  #
  #   ActiveRecord::SessionStore.session_class = MySessionClass
  #
  # You must implement these methods:
  #
  #   self.find_by_session_id(session_id)
  #   initialize(hash_of_session_id_and_data, options_hash = {})
  #   attr_reader :session_id
  #   attr_accessor :data
  #   save
  #   destroy
  #
  # The example SqlBypass class is a generic SQL session store. You may
  # use it as a basis for high-performance database-specific stores.
  class SessionStore < ActionDispatch::Session::AbstractStore
    module ClassMethods # :nodoc:
      def marshal(data)
        ::Base64.encode64(Marshal.dump(data)) if data
      end

      def unmarshal(data)
        Marshal.load(::Base64.decode64(data)) if data
      end

      def drop_table!
        connection.schema_cache.clear_table_cache!(table_name)
        connection.drop_table table_name
      end

      def create_table!
        connection.schema_cache.clear_table_cache!(table_name)
        connection.create_table(table_name) do |t|
          t.string session_id_column, :limit => 255
          t.text data_column_name
        end
        connection.add_index table_name, session_id_column, :unique => true
      end
    end

    # The default Active Record class.
    class Session < ActiveRecord::Base
      extend ClassMethods

      ##
      # :singleton-method:
      # Customizable data column name. Defaults to 'data'.
      cattr_accessor :data_column_name
      self.data_column_name = 'data'

      attr_accessible :session_id, :data, :marshaled_data

      before_save :marshal_data!
      before_save :raise_on_session_data_overflow!

      class << self
        def data_column_size_limit
          @data_column_size_limit ||= columns_hash[data_column_name].limit
        end

        # Hook to set up sessid compatibility.
        def find_by_session_id(session_id)
          setup_sessid_compatibility!
          find_by_session_id(session_id)
        end

        private
          def session_id_column
            'session_id'
          end

          # Compatibility with tables using sessid instead of session_id.
          def setup_sessid_compatibility!
            # Reset column info since it may be stale.
            reset_column_information
            if columns_hash['sessid']
              def self.find_by_session_id(*args)
                find_by_sessid(*args)
              end

              define_method(:session_id)  { sessid }
              define_method(:session_id=) { |session_id| self.sessid = session_id }
            else
              class << self; remove_method :find_by_session_id; end

              def self.find_by_session_id(session_id)
                find :first, :conditions => {:session_id=>session_id}
              end
            end
          end
      end

      def initialize(attributes = nil, options = {})
        @data = nil
        super
      end

      # Lazy-unmarshal session state.
      def data
        @data ||= self.class.unmarshal(read_attribute(@@data_column_name)) || {}
      end

      attr_writer :data

      # Has the session been loaded yet?
      def loaded?
        @data
      end

      private
        def marshal_data!
          return false unless loaded?
          write_attribute(@@data_column_name, self.class.marshal(data))
        end

        # Ensures that the data about to be stored in the database is not
        # larger than the data storage column. Raises
        # ActionController::SessionOverflowError.
        def raise_on_session_data_overflow!
          return false unless loaded?
          limit = self.class.data_column_size_limit
          if limit and read_attribute(@@data_column_name).size > limit
            raise ActionController::SessionOverflowError
          end
        end
    end

    # A barebones session store which duck-types with the default session
    # store but bypasses Active Record and issues SQL directly. This is
    # an example session model class meant as a basis for your own classes.
    #
    # The database connection, table name, and session id and data columns
    # are configurable class attributes. Marshaling and unmarshaling
    # are implemented as class methods that you may override. By default,
    # marshaling data is
    #
    #   ::Base64.encode64(Marshal.dump(data))
    #
    # and unmarshaling data is
    #
    #   Marshal.load(::Base64.decode64(data))
    #
    # This marshaling behavior is intended to store the widest range of
    # binary session data in a +text+ column. For higher performance,
    # store in a +blob+ column instead and forgo the Base64 encoding.
    class SqlBypass
      extend ClassMethods

      ##
      # :singleton-method:
      # The table name defaults to 'sessions'.
      cattr_accessor :table_name
      @@table_name = 'sessions'

      ##
      # :singleton-method:
      # The session id field defaults to 'session_id'.
      cattr_accessor :session_id_column
      @@session_id_column = 'session_id'

      ##
      # :singleton-method:
      # The data field defaults to 'data'.
      cattr_accessor :data_column
      @@data_column = 'data'

      class << self
        alias :data_column_name :data_column
        
        # Use the ActiveRecord::Base.connection by default.
        attr_writer :connection
        
        # Use the ActiveRecord::Base.connection_pool by default.
        attr_writer :connection_pool

        def connection
          @connection ||= ActiveRecord::Base.connection
        end

        def connection_pool
          @connection_pool ||= ActiveRecord::Base.connection_pool
        end

        # Look up a session by id and unmarshal its data if found.
        def find_by_session_id(session_id)
          if record = connection.select_one("SELECT * FROM #{@@table_name} WHERE #{@@session_id_column}=#{connection.quote(session_id)}")
            new(:session_id => session_id, :marshaled_data => record['data'])
          end
        end
      end
      
      delegate :connection, :connection=, :connection_pool, :connection_pool=, :to => self

      attr_reader :session_id, :new_record
      alias :new_record? :new_record

      attr_writer :data

      # Look for normal and marshaled data, self.find_by_session_id's way of
      # telling us to postpone unmarshaling until the data is requested.
      # We need to handle a normal data attribute in case of a new record.
      def initialize(attributes)
        @session_id     = attributes[:session_id]
        @data           = attributes[:data]
        @marshaled_data = attributes[:marshaled_data]
        @new_record     = @marshaled_data.nil?
      end

      # Lazy-unmarshal session state.
      def data
        unless @data
          if @marshaled_data
            @data, @marshaled_data = self.class.unmarshal(@marshaled_data) || {}, nil
          else
            @data = {}
          end
        end
        @data
      end

      def loaded?
        @data
      end

      def save
        return false unless loaded?
        marshaled_data = self.class.marshal(data)
        connect        = connection

        if @new_record
          @new_record = false
          connect.update <<-end_sql, 'Create session'
            INSERT INTO #{table_name} (
              #{connect.quote_column_name(session_id_column)},
              #{connect.quote_column_name(data_column)} )
            VALUES (
              #{connect.quote(session_id)},
              #{connect.quote(marshaled_data)} )
          end_sql
        else
          connect.update <<-end_sql, 'Update session'
            UPDATE #{table_name}
            SET #{connect.quote_column_name(data_column)}=#{connect.quote(marshaled_data)}
            WHERE #{connect.quote_column_name(session_id_column)}=#{connect.quote(session_id)}
          end_sql
        end
      end

      def destroy
        return if @new_record

        connect = connection
        connect.delete <<-end_sql, 'Destroy session'
          DELETE FROM #{table_name}
          WHERE #{connect.quote_column_name(session_id_column)}=#{connect.quote(session_id)}
        end_sql
      end
    end

    # The class used for session storage. Defaults to
    # ActiveRecord::SessionStore::Session
    cattr_accessor :session_class
    self.session_class = Session

    SESSION_RECORD_KEY = 'rack.session.record'
    ENV_SESSION_OPTIONS_KEY = Rack::Session::Abstract::ENV_SESSION_OPTIONS_KEY

    private
      def get_session(env, sid)
        Base.silence do
          unless sid and session = @@session_class.find_by_session_id(sid)
            # If the sid was nil or if there is no pre-existing session under the sid,
            # force the generation of a new sid and associate a new session associated with the new sid
            sid = generate_sid
            session = @@session_class.new(:session_id => sid, :data => {})
          end
          env[SESSION_RECORD_KEY] = session
          [sid, session.data]
        end
      end

      def set_session(env, sid, session_data, options)
        Base.silence do
          record = get_session_model(env, sid)
          record.data = session_data
          return false unless record.save

          session_data = record.data
          if session_data && session_data.respond_to?(:each_value)
            session_data.each_value do |obj|
              obj.clear_association_cache if obj.respond_to?(:clear_association_cache)
            end
          end
        end

        sid
      end

      def destroy_session(env, session_id, options)
        if sid = current_session_id(env)
          Base.silence do
            get_session_model(env, sid).destroy
            env[SESSION_RECORD_KEY] = nil
          end
        end

        generate_sid unless options[:drop]
      end

      def get_session_model(env, sid)
        if env[ENV_SESSION_OPTIONS_KEY][:id].nil?
          env[SESSION_RECORD_KEY] = find_session(sid)
        else
          env[SESSION_RECORD_KEY] ||= find_session(sid)
        end
      end

      def find_session(id)
        @@session_class.find_by_session_id(id) ||
          @@session_class.new(:session_id => id, :data => {})
      end
  end
end
module ActiveRecord
  # Store gives you a thin wrapper around serialize for the purpose of storing hashes in a single column.
  # It's like a simple key/value store backed into your record when you don't care about being able to
  # query that store outside the context of a single record.
  #
  # You can then declare accessors to this store that are then accessible just like any other attribute
  # of the model. This is very helpful for easily exposing store keys to a form or elsewhere that's
  # already built around just accessing attributes on the model.
  #
  # Make sure that you declare the database column used for the serialized store as a text, so there's
  # plenty of room.
  #
  # Examples:
  #
  #   class User < ActiveRecord::Base
  #     store :settings, accessors: [ :color, :homepage ]
  #   end
  #   
  #   u = User.new(color: 'black', homepage: '37signals.com')
  #   u.color                          # Accessor stored attribute
  #   u.settings[:country] = 'Denmark' # Any attribute, even if not specified with an accessor
  #
  #   # Add additional accessors to an existing store through store_accessor
  #   class SuperUser < User
  #     store_accessor :settings, :privileges, :servants
  #   end
  module Store
    extend ActiveSupport::Concern
  
    module ClassMethods
      def store(store_attribute, options = {})
        serialize store_attribute, Hash
        store_accessor(store_attribute, options[:accessors]) if options.has_key? :accessors
      end

      def store_accessor(store_attribute, *keys)
        Array(keys).flatten.each do |key|
          define_method("#{key}=") do |value|
            send("#{store_attribute}=", {}) unless send(store_attribute).is_a?(Hash)
            send(store_attribute)[key] = value
            send("#{store_attribute}_will_change!")
          end
    
          define_method(key) do
            send("#{store_attribute}=", {}) unless send(store_attribute).is_a?(Hash)
            send(store_attribute)[key]
          end
        end
      end
    end
  end
endmodule ActiveRecord
  # = Active Record Test Case
  #
  # Defines some test assertions to test against SQL queries.
  class TestCase < ActiveSupport::TestCase #:nodoc:
    setup :cleanup_identity_map

    def setup
      cleanup_identity_map
    end

    def cleanup_identity_map
      ActiveRecord::IdentityMap.clear
    end

    # Backport skip to Ruby 1.8. test/unit doesn't support it, so just
    # make it a noop.
    unless instance_methods.map(&:to_s).include?("skip")
      def skip(message)
      end
    end

    def assert_date_from_db(expected, actual, message = nil)
      # SybaseAdapter doesn't have a separate column type just for dates,
      # so the time is in the string and incorrectly formatted
      if current_adapter?(:SybaseAdapter)
        assert_equal expected.to_s, actual.to_date.to_s, message
      else
        assert_equal expected.to_s, actual.to_s, message
      end
    end

    def assert_sql(*patterns_to_match)
      ActiveRecord::SQLCounter.log = []
      yield
      ActiveRecord::SQLCounter.log
    ensure
      failed_patterns = []
      patterns_to_match.each do |pattern|
        failed_patterns << pattern unless ActiveRecord::SQLCounter.log.any?{ |sql| pattern === sql }
      end
      assert failed_patterns.empty?, "Query pattern(s) #{failed_patterns.map{ |p| p.inspect }.join(', ')} not found.#{ActiveRecord::SQLCounter.log.size == 0 ? '' : "\nQueries:\n#{ActiveRecord::SQLCounter.log.join("\n")}"}"
    end

    def assert_queries(num = 1)
      ActiveRecord::SQLCounter.log = []
      yield
    ensure
      assert_equal num, ActiveRecord::SQLCounter.log.size, "#{ActiveRecord::SQLCounter.log.size} instead of #{num} queries were executed.#{ActiveRecord::SQLCounter.log.size == 0 ? '' : "\nQueries:\n#{ActiveRecord::SQLCounter.log.join("\n")}"}"
    end

    def assert_no_queries(&block)
      prev_ignored_sql = ActiveRecord::SQLCounter.ignored_sql
      ActiveRecord::SQLCounter.ignored_sql = []
      assert_queries(0, &block)
    ensure
      ActiveRecord::SQLCounter.ignored_sql = prev_ignored_sql
    end

    def with_kcode(kcode)
      if RUBY_VERSION < '1.9'
        orig_kcode, $KCODE = $KCODE, kcode
        begin
          yield
        ensure
          $KCODE = orig_kcode
        end
      else
        yield
      end
    end
  end
end
require 'active_support/core_ext/class/attribute'

module ActiveRecord
  # = Active Record Timestamp
  #
  # Active Record automatically timestamps create and update operations if the
  # table has fields named <tt>created_at/created_on</tt> or
  # <tt>updated_at/updated_on</tt>.
  #
  # Timestamping can be turned off by setting:
  #
  #   config.active_record.record_timestamps = false
  #
  # Timestamps are in the local timezone by default but you can use UTC by setting:
  #
  #   config.active_record.default_timezone = :utc
  #
  # == Time Zone aware attributes
  #
  # By default, ActiveRecord::Base keeps all the datetime columns time zone aware by executing following code.
  #
  #   config.active_record.time_zone_aware_attributes = true
  #
  # This feature can easily be turned off by assigning value <tt>false</tt> .
  #
  # If your attributes are time zone aware and you desire to skip time zone conversion to the current Time.zone
  # when reading certain attributes then you can do following:
  #
  #   class Topic < ActiveRecord::Base
  #     self.skip_time_zone_conversion_for_attributes = [:written_on]
  #   end
  module Timestamp
    extend ActiveSupport::Concern

    included do
      class_attribute :record_timestamps
      self.record_timestamps = true
    end

    def initialize_dup(other)
      clear_timestamp_attributes
      super
    end

  private

    def create #:nodoc:
      if self.record_timestamps
        current_time = current_time_from_proper_timezone

        all_timestamp_attributes.each do |column|
          if respond_to?(column) && respond_to?("#{column}=") && self.send(column).nil?
            write_attribute(column.to_s, current_time)
          end
        end
      end

      super
    end

    def update(*args) #:nodoc:
      if should_record_timestamps?
        current_time = current_time_from_proper_timezone

        timestamp_attributes_for_update_in_model.each do |column|
          column = column.to_s
          next if attribute_changed?(column)
          write_attribute(column, current_time)
        end
      end
      super
    end

    def should_record_timestamps?
      self.record_timestamps && (!partial_updates? || changed? || (attributes.keys & self.class.serialized_attributes.keys).present?)
    end

    def timestamp_attributes_for_create_in_model
      timestamp_attributes_for_create.select { |c| self.class.column_names.include?(c.to_s) }
    end

    def timestamp_attributes_for_update_in_model
      timestamp_attributes_for_update.select { |c| self.class.column_names.include?(c.to_s) }
    end

    def all_timestamp_attributes_in_model
      timestamp_attributes_for_create_in_model + timestamp_attributes_for_update_in_model
    end

    def timestamp_attributes_for_update #:nodoc:
      [:updated_at, :updated_on]
    end

    def timestamp_attributes_for_create #:nodoc:
      [:created_at, :created_on]
    end

    def all_timestamp_attributes #:nodoc:
      timestamp_attributes_for_create + timestamp_attributes_for_update
    end

    def current_time_from_proper_timezone #:nodoc:
      self.class.default_timezone == :utc ? Time.now.utc : Time.now
    end

    # Clear attributes and changed_attributes
    def clear_timestamp_attributes
      all_timestamp_attributes_in_model.each do |attribute_name|
        self[attribute_name] = nil
        changed_attributes.delete(attribute_name)
      end
    end
  end
end
require 'thread'

module ActiveRecord
  # See ActiveRecord::Transactions::ClassMethods for documentation.
  module Transactions
    extend ActiveSupport::Concern

    class TransactionError < ActiveRecordError # :nodoc:
    end

    included do
      define_callbacks :commit, :rollback, :terminator => "result == false", :scope => [:kind, :name]
    end

    # = Active Record Transactions
    #
    # Transactions are protective blocks where SQL statements are only permanent
    # if they can all succeed as one atomic action. The classic example is a
    # transfer between two accounts where you can only have a deposit if the
    # withdrawal succeeded and vice versa. Transactions enforce the integrity of
    # the database and guard the data against program errors or database
    # break-downs. So basically you should use transaction blocks whenever you
    # have a number of statements that must be executed together or not at all.
    #
    # For example:
    #
    #   ActiveRecord::Base.transaction do
    #     david.withdrawal(100)
    #     mary.deposit(100)
    #   end
    #
    # This example will only take money from David and give it to Mary if neither
    # +withdrawal+ nor +deposit+ raise an exception. Exceptions will force a
    # ROLLBACK that returns the database to the state before the transaction
    # began. Be aware, though, that the objects will _not_ have their instance
    # data returned to their pre-transactional state.
    #
    # == Different Active Record classes in a single transaction
    #
    # Though the transaction class method is called on some Active Record class,
    # the objects within the transaction block need not all be instances of
    # that class. This is because transactions are per-database connection, not
    # per-model.
    #
    # In this example a +balance+ record is transactionally saved even
    # though +transaction+ is called on the +Account+ class:
    #
    #   Account.transaction do
    #     balance.save!
    #     account.save!
    #   end
    #
    # The +transaction+ method is also available as a model instance method.
    # For example, you can also do this:
    #
    #   balance.transaction do
    #     balance.save!
    #     account.save!
    #   end
    #
    # == Transactions are not distributed across database connections
    #
    # A transaction acts on a single database connection. If you have
    # multiple class-specific databases, the transaction will not protect
    # interaction among them. One workaround is to begin a transaction
    # on each class whose models you alter:
    #
    #   Student.transaction do
    #     Course.transaction do
    #       course.enroll(student)
    #       student.units += course.units
    #     end
    #   end
    #
    # This is a poor solution, but fully distributed transactions are beyond
    # the scope of Active Record.
    #
    # == +save+ and +destroy+ are automatically wrapped in a transaction
    #
    # Both +save+ and +destroy+ come wrapped in a transaction that ensures
    # that whatever you do in validations or callbacks will happen under its
    # protected cover. So you can use validations to check for values that
    # the transaction depends on or you can raise exceptions in the callbacks
    # to rollback, including <tt>after_*</tt> callbacks.
    #
    # As a consequence changes to the database are not seen outside your connection
    # until the operation is complete. For example, if you try to update the index
    # of a search engine in +after_save+ the indexer won't see the updated record.
    # The +after_commit+ callback is the only one that is triggered once the update
    # is committed. See below.
    #
    # == Exception handling and rolling back
    #
    # Also have in mind that exceptions thrown within a transaction block will
    # be propagated (after triggering the ROLLBACK), so you should be ready to
    # catch those in your application code.
    #
    # One exception is the <tt>ActiveRecord::Rollback</tt> exception, which will trigger
    # a ROLLBACK when raised, but not be re-raised by the transaction block.
    #
    # *Warning*: one should not catch <tt>ActiveRecord::StatementInvalid</tt> exceptions
    # inside a transaction block. <tt>ActiveRecord::StatementInvalid</tt> exceptions indicate that an
    # error occurred at the database level, for example when a unique constraint
    # is violated. On some database systems, such as PostgreSQL, database errors
    # inside a transaction cause the entire transaction to become unusable
    # until it's restarted from the beginning. Here is an example which
    # demonstrates the problem:
    #
    #   # Suppose that we have a Number model with a unique column called 'i'.
    #   Number.transaction do
    #     Number.create(:i => 0)
    #     begin
    #       # This will raise a unique constraint error...
    #       Number.create(:i => 0)
    #     rescue ActiveRecord::StatementInvalid
    #       # ...which we ignore.
    #     end
    #
    #     # On PostgreSQL, the transaction is now unusable. The following
    #     # statement will cause a PostgreSQL error, even though the unique
    #     # constraint is no longer violated:
    #     Number.create(:i => 1)
    #     # => "PGError: ERROR:  current transaction is aborted, commands
    #     #     ignored until end of transaction block"
    #   end
    #
    # One should restart the entire transaction if an
    # <tt>ActiveRecord::StatementInvalid</tt> occurred.
    #
    # == Nested transactions
    #
    # +transaction+ calls can be nested. By default, this makes all database
    # statements in the nested transaction block become part of the parent
    # transaction. For example, the following behavior may be surprising:
    #
    #   User.transaction do
    #     User.create(:username => 'Kotori')
    #     User.transaction do
    #       User.create(:username => 'Nemu')
    #       raise ActiveRecord::Rollback
    #     end
    #   end
    #
    # creates both "Kotori" and "Nemu". Reason is the <tt>ActiveRecord::Rollback</tt>
    # exception in the nested block does not issue a ROLLBACK. Since these exceptions
    # are captured in transaction blocks, the parent block does not see it and the
    # real transaction is committed.
    #
    # In order to get a ROLLBACK for the nested transaction you may ask for a real
    # sub-transaction by passing <tt>:requires_new => true</tt>. If anything goes wrong,
    # the database rolls back to the beginning of the sub-transaction without rolling
    # back the parent transaction. If we add it to the previous example:
    #
    #   User.transaction do
    #     User.create(:username => 'Kotori')
    #     User.transaction(:requires_new => true) do
    #       User.create(:username => 'Nemu')
    #       raise ActiveRecord::Rollback
    #     end
    #   end
    #
    # only "Kotori" is created. (This works on MySQL and PostgreSQL, but not on SQLite3.)
    #
    # Most databases don't support true nested transactions. At the time of
    # writing, the only database that we're aware of that supports true nested
    # transactions, is MS-SQL. Because of this, Active Record emulates nested
    # transactions by using savepoints on MySQL and PostgreSQL. See
    # http://dev.mysql.com/doc/refman/5.0/en/savepoint.html
    # for more information about savepoints.
    #
    # === Callbacks
    #
    # There are two types of callbacks associated with committing and rolling back transactions:
    # +after_commit+ and +after_rollback+.
    #
    # +after_commit+ callbacks are called on every record saved or destroyed within a
    # transaction immediately after the transaction is committed. +after_rollback+ callbacks
    # are called on every record saved or destroyed within a transaction immediately after the
    # transaction or savepoint is rolled back.
    #
    # These callbacks are useful for interacting with other systems since you will be guaranteed
    # that the callback is only executed when the database is in a permanent state. For example,
    # +after_commit+ is a good spot to put in a hook to clearing a cache since clearing it from
    # within a transaction could trigger the cache to be regenerated before the database is updated.
    #
    # === Caveats
    #
    # If you're on MySQL, then do not use DDL operations in nested transactions
    # blocks that are emulated with savepoints. That is, do not execute statements
    # like 'CREATE TABLE' inside such blocks. This is because MySQL automatically
    # releases all savepoints upon executing a DDL operation. When +transaction+
    # is finished and tries to release the savepoint it created earlier, a
    # database error will occur because the savepoint has already been
    # automatically released. The following example demonstrates the problem:
    #
    #   Model.connection.transaction do                           # BEGIN
    #     Model.connection.transaction(:requires_new => true) do  # CREATE SAVEPOINT active_record_1
    #       Model.connection.create_table(...)                    # active_record_1 now automatically released
    #     end                                                     # RELEASE savepoint active_record_1
    #                                                             # ^^^^ BOOM! database error!
    #   end
    #
    # Note that "TRUNCATE" is also a MySQL DDL statement!
    module ClassMethods
      # See ActiveRecord::Transactions::ClassMethods for detailed documentation.
      def transaction(options = {}, &block)
        # See the ConnectionAdapters::DatabaseStatements#transaction API docs.
        connection.transaction(options, &block)
      end

      # This callback is called after a record has been created, updated, or destroyed.
      #
      # You can specify that the callback should only be fired by a certain action with
      # the +:on+ option:
      #
      #   after_commit :do_foo, :on => :create
      #   after_commit :do_bar, :on => :update
      #   after_commit :do_baz, :on => :destroy
      #
      # Also, to have the callback fired on create and update, but not on destroy:
      #
      #   after_commit :do_zoo, :if => :persisted?
      #
      # Note that transactional fixtures do not play well with this feature. Please
      # use the +test_after_commit+ gem to have these hooks fired in tests.
      def after_commit(*args, &block)
        options = args.last
        if options.is_a?(Hash) && options[:on]
          options[:if] = Array.wrap(options[:if])
          options[:if] << "transaction_include_action?(:#{options[:on]})"
        end
        set_callback(:commit, :after, *args, &block)
      end

      # This callback is called after a create, update, or destroy are rolled back.
      #
      # Please check the documentation of +after_commit+ for options.
      def after_rollback(*args, &block)
        options = args.last
        if options.is_a?(Hash) && options[:on]
          options[:if] = Array.wrap(options[:if])
          options[:if] << "transaction_include_action?(:#{options[:on]})"
        end
        set_callback(:rollback, :after, *args, &block)
      end
    end

    # See ActiveRecord::Transactions::ClassMethods for detailed documentation.
    def transaction(options = {}, &block)
      self.class.transaction(options, &block)
    end

    def destroy #:nodoc:
      with_transaction_returning_status { super }
    end

    def save(*) #:nodoc:
      rollback_active_record_state! do
        with_transaction_returning_status { super }
      end
    end

    def save!(*) #:nodoc:
      with_transaction_returning_status { super }
    end

    # Reset id and @new_record if the transaction rolls back.
    def rollback_active_record_state!
      remember_transaction_record_state
      yield
    rescue Exception
      IdentityMap.remove(self) if IdentityMap.enabled?
      restore_transaction_record_state
      raise
    ensure
      clear_transaction_record_state
    end

    # Call the after_commit callbacks
    def committed! #:nodoc:
      run_callbacks :commit
    ensure
      clear_transaction_record_state
    end

    # Call the after rollback callbacks. The restore_state argument indicates if the record
    # state should be rolled back to the beginning or just to the last savepoint.
    def rolledback!(force_restore_state = false) #:nodoc:
      run_callbacks :rollback
    ensure
      IdentityMap.remove(self) if IdentityMap.enabled?
      restore_transaction_record_state(force_restore_state)
    end

    # Add the record to the current transaction so that the :after_rollback and :after_commit callbacks
    # can be called.
    def add_to_transaction
      if self.class.connection.add_transaction_record(self)
        remember_transaction_record_state
      end
    end

    # Executes +method+ within a transaction and captures its return value as a
    # status flag. If the status is true the transaction is committed, otherwise
    # a ROLLBACK is issued. In any case the status flag is returned.
    #
    # This method is available within the context of an ActiveRecord::Base
    # instance.
    def with_transaction_returning_status
      status = nil
      self.class.transaction do
        add_to_transaction
        status = yield
        raise ActiveRecord::Rollback unless status
      end
      status
    end

    protected

    # Save the new record state and id of a record so it can be restored later if a transaction fails.
    def remember_transaction_record_state #:nodoc:
      @_start_transaction_state ||= {}
      @_start_transaction_state[:id] = id if has_attribute?(self.class.primary_key)
      unless @_start_transaction_state.include?(:new_record)
        @_start_transaction_state[:new_record] = @new_record
      end
      unless @_start_transaction_state.include?(:destroyed)
        @_start_transaction_state[:destroyed] = @destroyed
      end
      @_start_transaction_state[:level] = (@_start_transaction_state[:level] || 0) + 1
      @_start_transaction_state[:frozen?] = @attributes.frozen?
    end

    # Clear the new record state and id of a record.
    def clear_transaction_record_state #:nodoc:
      if defined?(@_start_transaction_state)
        @_start_transaction_state[:level] = (@_start_transaction_state[:level] || 0) - 1
        remove_instance_variable(:@_start_transaction_state) if @_start_transaction_state[:level] < 1
      end
    end

    # Restore the new record state and id of a record that was previously saved by a call to save_record_state.
    def restore_transaction_record_state(force = false) #:nodoc:
      if defined?(@_start_transaction_state)
        @_start_transaction_state[:level] = (@_start_transaction_state[:level] || 0) - 1
        if @_start_transaction_state[:level] < 1 || force
          restore_state = remove_instance_variable(:@_start_transaction_state)
          was_frozen = restore_state[:frozen?]
          @attributes = @attributes.dup if @attributes.frozen?
          @new_record = restore_state[:new_record]
          @destroyed  = restore_state[:destroyed]
          if restore_state.has_key?(:id)
            self.id = restore_state[:id]
          else
            @attributes.delete(self.class.primary_key)
            @attributes_cache.delete(self.class.primary_key)
          end
          @attributes.freeze if was_frozen
        end
      end
    end

    # Determine if a record was created or destroyed in a transaction. State should be one of :new_record or :destroyed.
    def transaction_record_state(state) #:nodoc:
      @_start_transaction_state[state] if defined?(@_start_transaction_state)
    end

    # Determine if a transaction included an action for :create, :update, or :destroy. Used in filtering callbacks.
    def transaction_include_action?(action) #:nodoc:
      case action
      when :create
        transaction_record_state(:new_record)
      when :destroy
        destroyed?
      when :update
        !(transaction_record_state(:new_record) || destroyed?)
      end
    end
  end
end
module ActiveRecord
  module Translation
    include ActiveModel::Translation

    # Set the lookup ancestors for ActiveModel.
    def lookup_ancestors #:nodoc:
      klass = self
      classes = [klass]
      return classes if klass == ActiveRecord::Base

      while klass != klass.base_class
        classes << klass = klass.superclass
      end
      classes
    end

    # Set the i18n scope to overwrite ActiveModel.
    def i18n_scope #:nodoc:
      :activerecord
    end
  end
end
module ActiveRecord
  module Validations
    class AssociatedValidator < ActiveModel::EachValidator
      def validate_each(record, attribute, value)
        if Array.wrap(value).reject {|r| r.marked_for_destruction? || r.valid?}.any?
          record.errors.add(attribute, :invalid, options.merge(:value => value))
        end
      end
    end

    module ClassMethods
      # Validates whether the associated object or objects are all valid themselves. Works with any kind of association.
      #
      #   class Book < ActiveRecord::Base
      #     has_many :pages
      #     belongs_to :library
      #
      #     validates_associated :pages, :library
      #   end
      #
      # WARNING: This validation must not be used on both ends of an association. Doing so will lead to a circular dependency and cause infinite recursion.
      #
      # NOTE: This validation will not fail if the association hasn't been assigned. If you want to
      # ensure that the association is both present and guaranteed to be valid, you also need to
      # use +validates_presence_of+.
      #
      # Configuration options:
      # * <tt>:message</tt> - A custom error message (default is: "is invalid")
      # * <tt>:on</tt> - Specifies when this validation is active. Runs in all
      #   validation contexts by default (+nil+), other options are <tt>:create</tt>
      #   and <tt>:update</tt>.
      # * <tt>:if</tt> - Specifies a method, proc or string to call to determine if the validation should
      #   occur (e.g. <tt>:if => :allow_validation</tt>, or <tt>:if => Proc.new { |user| user.signup_step > 2 }</tt>). The
      #   method, proc or string should return or evaluate to a true or false value.
      # * <tt>:unless</tt> - Specifies a method, proc or string to call to determine if the validation should
      #   not occur (e.g. <tt>:unless => :skip_validation</tt>, or <tt>:unless => Proc.new { |user| user.signup_step <= 2 }</tt>). The
      #   method, proc or string should return or evaluate to a true or false value.
      def validates_associated(*attr_names)
        validates_with AssociatedValidator, _merge_attributes(attr_names)
      end
    end
  end
end
require 'active_support/core_ext/array/wrap'

module ActiveRecord
  module Validations
    class UniquenessValidator < ActiveModel::EachValidator
      def initialize(options)
        super(options.reverse_merge(:case_sensitive => true))
      end

      # Unfortunately, we have to tie Uniqueness validators to a class.
      def setup(klass)
        @klass = klass
      end

      def validate_each(record, attribute, value)
        finder_class = find_finder_class_for(record)
        table = finder_class.arel_table

        coder = record.class.serialized_attributes[attribute.to_s]

        if value && coder
          value = coder.dump value
        end

        relation = build_relation(finder_class, table, attribute, value)
        relation = relation.and(table[finder_class.primary_key.to_sym].not_eq(record.send(:id))) if record.persisted?

        Array.wrap(options[:scope]).each do |scope_item|
          scope_value = record.send(scope_item)
          relation = relation.and(table[scope_item].eq(scope_value))
        end

        if finder_class.unscoped.where(relation).exists?
          record.errors.add(attribute, :taken, options.except(:case_sensitive, :scope).merge(:value => value))
        end
      end

    protected

      # The check for an existing value should be run from a class that
      # isn't abstract. This means working down from the current class
      # (self), to the first non-abstract class. Since classes don't know
      # their subclasses, we have to build the hierarchy between self and
      # the record's class.
      def find_finder_class_for(record) #:nodoc:
        class_hierarchy = [record.class]

        while class_hierarchy.first != @klass
          class_hierarchy.insert(0, class_hierarchy.first.superclass)
        end

        class_hierarchy.detect { |klass| !klass.abstract_class? }
      end

      def build_relation(klass, table, attribute, value) #:nodoc:
        column = klass.columns_hash[attribute.to_s]
        value = column.limit ? value.to_s.mb_chars[0, column.limit] : value.to_s if value && column.text?

        if !options[:case_sensitive] && value && column.text?
          # will use SQL LOWER function before comparison, unless it detects a case insensitive collation
          relation = klass.connection.case_insensitive_comparison(table, attribute, column, value)
        else
          value    = klass.connection.case_sensitive_modifier(value) if value
          relation = table[attribute].eq(value)
        end

        relation
      end
    end

    module ClassMethods
      # Validates whether the value of the specified attributes are unique across the system.
      # Useful for making sure that only one user
      # can be named "davidhh".
      #
      #   class Person < ActiveRecord::Base
      #     validates_uniqueness_of :user_name
      #   end
      #
      # It can also validate whether the value of the specified attributes are unique based on a scope parameter:
      #
      #   class Person < ActiveRecord::Base
      #     validates_uniqueness_of :user_name, :scope => :account_id
      #   end
      #
      # Or even multiple scope parameters. For example, making sure that a teacher can only be on the schedule once
      # per semester for a particular class.
      #
      #   class TeacherSchedule < ActiveRecord::Base
      #     validates_uniqueness_of :teacher_id, :scope => [:semester_id, :class_id]
      #   end
      #
      # When the record is created, a check is performed to make sure that no record exists in the database
      # with the given value for the specified attribute (that maps to a column). When the record is updated,
      # the same check is made but disregarding the record itself.
      #
      # Configuration options:
      # * <tt>:message</tt> - Specifies a custom error message (default is: "has already been taken").
      # * <tt>:scope</tt> - One or more columns by which to limit the scope of the uniqueness constraint.
      # * <tt>:case_sensitive</tt> - Looks for an exact match. Ignored by non-text columns (+true+ by default).
      # * <tt>:allow_nil</tt> - If set to true, skips this validation if the attribute is +nil+ (default is +false+).
      # * <tt>:allow_blank</tt> - If set to true, skips this validation if the attribute is blank (default is +false+).
      # * <tt>:if</tt> - Specifies a method, proc or string to call to determine if the validation should
      #   occur (e.g. <tt>:if => :allow_validation</tt>, or <tt>:if => Proc.new { |user| user.signup_step > 2 }</tt>).
      #   The method, proc or string should return or evaluate to a true or false value.
      # * <tt>:unless</tt> - Specifies a method, proc or string to call to determine if the validation should
      #   not occur (e.g. <tt>:unless => :skip_validation</tt>, or
      #   <tt>:unless => Proc.new { |user| user.signup_step <= 2 }</tt>). The method, proc or string should
      #   return or evaluate to a true or false value.
      #
      # === Concurrency and integrity
      #
      # Using this validation method in conjunction with ActiveRecord::Base#save
      # does not guarantee the absence of duplicate record insertions, because
      # uniqueness checks on the application level are inherently prone to race
      # conditions. For example, suppose that two users try to post a Comment at
      # the same time, and a Comment's title must be unique. At the database-level,
      # the actions performed by these users could be interleaved in the following manner:
      #
      #               User 1                 |               User 2
      #  ------------------------------------+--------------------------------------
      #  # User 1 checks whether there's     |
      #  # already a comment with the title  |
      #  # 'My Post'. This is not the case.  |
      #  SELECT * FROM comments              |
      #  WHERE title = 'My Post'             |
      #                                      |
      #                                      | # User 2 does the same thing and also
      #                                      | # infers that his title is unique.
      #                                      | SELECT * FROM comments
      #                                      | WHERE title = 'My Post'
      #                                      |
      #  # User 1 inserts his comment.       |
      #  INSERT INTO comments                |
      #  (title, content) VALUES             |
      #  ('My Post', 'hi!')                  |
      #                                      |
      #                                      | # User 2 does the same thing.
      #                                      | INSERT INTO comments
      #                                      | (title, content) VALUES
      #                                      | ('My Post', 'hello!')
      #                                      |
      #                                      | # ^^^^^^
      #                                      | # Boom! We now have a duplicate
      #                                      | # title!
      #
      # This could even happen if you use transactions with the 'serializable'
      # isolation level. The best way to work around this problem is to add a unique
      # index to the database table using
      # ActiveRecord::ConnectionAdapters::SchemaStatements#add_index. In the
      # rare case that a race condition occurs, the database will guarantee
      # the field's uniqueness.
      #
      # When the database catches such a duplicate insertion,
      # ActiveRecord::Base#save will raise an ActiveRecord::StatementInvalid
      # exception. You can either choose to let this error propagate (which
      # will result in the default Rails exception page being shown), or you
      # can catch it and restart the transaction (e.g. by telling the user
      # that the title already exists, and asking him to re-enter the title).
      # This technique is also known as optimistic concurrency control:
      # http://en.wikipedia.org/wiki/Optimistic_concurrency_control
      #
      # The bundled ActiveRecord::ConnectionAdapters distinguish unique index
      # constraint errors from other types of database errors by throwing an
      # ActiveRecord::RecordNotUnique exception.
      # For other adapters you will have to parse the (database-specific) exception
      # message to detect such a case.
      # The following bundled adapters throw the ActiveRecord::RecordNotUnique exception:
      # * ActiveRecord::ConnectionAdapters::MysqlAdapter
      # * ActiveRecord::ConnectionAdapters::Mysql2Adapter
      # * ActiveRecord::ConnectionAdapters::SQLiteAdapter
      # * ActiveRecord::ConnectionAdapters::SQLite3Adapter
      # * ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
      #
      def validates_uniqueness_of(*attr_names)
        validates_with UniquenessValidator, _merge_attributes(attr_names)
      end
    end
  end
end
module ActiveRecord
  # = Active Record RecordInvalid
  #
  # Raised by <tt>save!</tt> and <tt>create!</tt> when the record is invalid. Use the
  # +record+ method to retrieve the record which did not validate.
  #
  #   begin
  #     complex_operation_that_calls_save!_internally
  #   rescue ActiveRecord::RecordInvalid => invalid
  #     puts invalid.record.errors
  #   end
  class RecordInvalid < ActiveRecordError
    attr_reader :record
    def initialize(record)
      @record = record
      errors = @record.errors.full_messages.join(", ")
      super(I18n.t("activerecord.errors.messages.record_invalid", :errors => errors))
    end
  end

  # = Active Record Validations
  #
  # Active Record includes the majority of its validations from <tt>ActiveModel::Validations</tt>
  # all of which accept the <tt>:on</tt> argument to define the context where the
  # validations are active. Active Record will always supply either the context of
  # <tt>:create</tt> or <tt>:update</tt> dependent on whether the model is a
  # <tt>new_record?</tt>.
  module Validations
    extend ActiveSupport::Concern
    include ActiveModel::Validations

    module ClassMethods
      # Creates an object just like Base.create but calls <tt>save!</tt> instead of +save+
      # so an exception is raised if the record is invalid.
      def create!(attributes = nil, options = {}, &block)
        if attributes.is_a?(Array)
          attributes.collect { |attr| create!(attr, options, &block) }
        else
          object = new(attributes, options)
          yield(object) if block_given?
          object.save!
          object
        end
      end
    end

    # The validation process on save can be skipped by passing <tt>:validate => false</tt>. The regular Base#save method is
    # replaced with this when the validations module is mixed in, which it is by default.
    def save(options={})
      perform_validations(options) ? super : false
    end

    # Attempts to save the record just like Base#save but will raise a +RecordInvalid+ exception instead of returning false
    # if the record is not valid.
    def save!(options={})
      perform_validations(options) ? super : raise(RecordInvalid.new(self))
    end

    # Runs all the validations within the specified context. Returns true if no errors are found,
    # false otherwise.
    #
    # If the argument is false (default is +nil+), the context is set to <tt>:create</tt> if
    # <tt>new_record?</tt> is true, and to <tt>:update</tt> if it is not.
    #
    # Validations with no <tt>:on</tt> option will run no matter the context. Validations with
    # some <tt>:on</tt> option will only run in the specified context.
    def valid?(context = nil)
      context ||= (new_record? ? :create : :update)
      output = super(context)
      errors.empty? && output
    end

  protected

    def perform_validations(options={})
      perform_validation = options[:validate] != false
      perform_validation ? valid?(options[:context]) : true
    end
  end
end

require "active_record/validations/associated"
require "active_record/validations/uniqueness"
module ActiveRecord
  module VERSION #:nodoc:
    MAJOR = 3
    MINOR = 2
    TINY  = 12
    PRE   = nil

    STRING = [MAJOR, MINOR, TINY, PRE].compact.join('.')
  end
end
#--
# Copyright (c) 2004-2011 David Heinemeier Hansson
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'active_support'
require 'active_support/i18n'
require 'active_model'
require 'arel'

require 'active_record/version'

module ActiveRecord
  extend ActiveSupport::Autoload

  # ActiveRecord::SessionStore depends on the abstract store in Action Pack.
  # Eager loading this class would break client code that eager loads Active
  # Record standalone.
  #
  # Note that the Rails application generator creates an initializer specific
  # for setting the session store. Thus, albeit in theory this autoload would
  # not be thread-safe, in practice it is because if the application uses this
  # session store its autoload happens at boot time.
  autoload :SessionStore

  eager_autoload do
    autoload :ActiveRecordError, 'active_record/errors'
    autoload :ConnectionNotEstablished, 'active_record/errors'
    autoload :ConnectionAdapters, 'active_record/connection_adapters/abstract_adapter'

    autoload :Aggregations
    autoload :Associations
    autoload :AttributeMethods
    autoload :AttributeAssignment
    autoload :AutosaveAssociation

    autoload :Relation

    autoload_under 'relation' do
      autoload :QueryMethods
      autoload :FinderMethods
      autoload :Calculations
      autoload :PredicateBuilder
      autoload :SpawnMethods
      autoload :Batches
      autoload :Explain
      autoload :Delegation
    end

    autoload :Base
    autoload :Callbacks
    autoload :CounterCache
    autoload :DynamicMatchers
    autoload :DynamicFinderMatch
    autoload :DynamicScopeMatch
    autoload :Explain
    autoload :IdentityMap
    autoload :Inheritance
    autoload :Integration
    autoload :Migration
    autoload :Migrator, 'active_record/migration'
    autoload :ModelSchema
    autoload :NestedAttributes
    autoload :Observer
    autoload :Persistence
    autoload :QueryCache
    autoload :Querying
    autoload :ReadonlyAttributes
    autoload :Reflection
    autoload :Result
    autoload :Sanitization
    autoload :Schema
    autoload :SchemaDumper
    autoload :Scoping
    autoload :Serialization
    autoload :Store
    autoload :Timestamp
    autoload :Transactions
    autoload :Translation
    autoload :Validations
  end

  module Coders
    autoload :YAMLColumn, 'active_record/coders/yaml_column'
  end

  module AttributeMethods
    extend ActiveSupport::Autoload

    eager_autoload do
      autoload :BeforeTypeCast
      autoload :Dirty
      autoload :PrimaryKey
      autoload :Query
      autoload :Read
      autoload :TimeZoneConversion
      autoload :Write
      autoload :Serialization
      autoload :DeprecatedUnderscoreRead
    end
  end

  module Locking
    extend ActiveSupport::Autoload

    eager_autoload do
      autoload :Optimistic
      autoload :Pessimistic
    end
  end

  module ConnectionAdapters
    extend ActiveSupport::Autoload

    eager_autoload do
      autoload :AbstractAdapter
      autoload :ConnectionManagement, "active_record/connection_adapters/abstract/connection_pool"
    end
  end

  module Scoping
    extend ActiveSupport::Autoload

    eager_autoload do
      autoload :Named
      autoload :Default
    end
  end

  autoload :TestCase
  autoload :TestFixtures, 'active_record/fixtures'
end

ActiveSupport.on_load(:active_record) do
  Arel::Table.engine = self
end

I18n.load_path << File.dirname(__FILE__) + '/active_record/locale/en.yml'
require 'rails/generators/active_record'

module ActiveRecord
  module Generators
    class MigrationGenerator < Base
      argument :attributes, :type => :array, :default => [], :banner => "field[:type][:index] field[:type][:index]"

      def create_migration_file
        set_local_assigns!
        migration_template "migration.rb", "db/migrate/#{file_name}.rb"
      end

      protected
        attr_reader :migration_action

        def set_local_assigns!
          if file_name =~ /^(add|remove)_.*_(?:to|from)_(.*)/
            @migration_action = $1
            @table_name       = $2.pluralize
          end
        end

    end
  end
end
