module VMS
  def self.basic_type?(variable)
    [Integer, Float, String, Symbol, TrueClass, FalseClass, NilClass].any? { |type| variable.is_a?(type) }
  end

  def self.encrypt(data)
    ret = {:class => data.class}
    data.instance_variables.each do |var|
      variable = data.instance_variable_get(var)
      if variable.is_a?(Array)
        index = 0
        ret[var] = { :class => variable.class }.merge(variable.each_with_object({}) do |var2, hash2|
          if VMS.basic_type?(var2)
            hash2["#{index}"] = var2
          else
            hash2["#{index}"] = VMS.encrypt(var2)
          end
          index += 1
        end)
      elsif variable.is_a?(Hash)
        ret[var] = { :class => variable.class }.merge(variable.each_with_object({}) do |var2, hash2|
          key = var2[0]
          value = var2[1]
          if VMS.basic_type?(value)
            hash2[key] = value
          else
            hash2[key] = VMS.encrypt(value)
          end
        end)
      elsif VMS.basic_type?(variable)
        ret[var] = variable
      else
        ret[var] = VMS.encrypt(variable)
      end
    end
    return ret
  end

  def self.decrypt(data, instance = nil)
    return data unless data.is_a?(Hash)
    defaults = VMS::ENCRYPTION_DEFAULTS[data[:class].name]
    case data[:class]
    when Array
      instance ||= []
    when Hash
      instance ||= {}
    else
      if data[:class].is_a?(Class) && data[:class].respond_to?(:new)
        if VMS::ENCRYPTION_DEFAULTS.key?(data[:class].name)
          case data[:class].name
          when "Pokemon" then instance ||= Pokemon.new(defaults[0], defaults[1])
          when "Pokemon::Move" then instance ||= Pokemon::Move.new(defaults[0])
          when "Pokemon::Owner" then instance ||= Pokemon::Owner.new(defaults[0], defaults[1], defaults[2], defaults[3])
          when "Battle::Move" then instance ||= Pokemon::Item.new(defaults[0])
          end
        else
          required_params = data[:class].instance_method(:initialize).parameters.select { |type, _name| type == :req }.map { |_type, name| name }
          if required_params.empty?
            instance ||= data[:class].new
          else
            # For simplicity, assuming all required parameters have default values
            default_values = Hash[required_params.map { |param| nil }]
            instance ||= data[:class].new(*default_values)
          end
        end
      end
    end 
    data.each do |var, val|
      next if var == :class
      if var.is_a?(String) && var.numeric?
        instance[var.to_i] = VMS.decrypt(val)
      elsif data[:class] == Hash
        instance[var] = VMS.decrypt(val)
      else
        instance.instance_variable_set(var, VMS.decrypt(val))
      end
    end
    return instance
  end

  def self.string_to_integer(str)
    prime = 31
    hash = 0
    str.each_char do |char|
      hash = (prime * hash + char.ord) % (2**31)
    end
    return hash
  end

  def self.array_compare(arr1, arr2)
    return false unless arr1.is_a?(Array) && arr2.is_a?(Array) && arr1.length == arr2.length
    return arr1 & arr2 == arr1
  end
end