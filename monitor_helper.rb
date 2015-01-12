module MonitorHelper
  def self.included(klass)
    klass.extend ClassMethods
  end

  module ClassMethods
    def make_safe(method)
      imp = "_#{method}"
      instance_eval do
        alias_method(imp, method)
        define_method(method) do |*args, &block|
          # @lock という Monitor オブジェクトの存在を仮定している
          @lock.synchronize do
            send(imp, *args, &block)
          end
        end
      end
    end
  end
end
