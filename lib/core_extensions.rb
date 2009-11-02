unless :to_proc.respond_to?(:to_proc)
  class Symbol
    def to_proc
      Proc.new { |*args| args.shift.__send__(self, *args) }
    end
  end
end

unless [].respond_to?(:shuffle)
  class Array
    def shuffle
      self.map { |e| [e, rand] }.sort_by(&:last).map(&:first)
    end
  end
end
