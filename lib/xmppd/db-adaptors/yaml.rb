#storages to be implemented:

#attr_accessor :last, :offline_stanzas, :vcard
#attr_reader   :node, :domain, :password, :resources, :roster


module DB

class Yaml
  
  def load_users
    begin
      @users = YAML.load(File.read('var/db/users.yaml'))
      @users ||= {}
    rescue Exception => e
      puts "xmppd: failed to load user database: #{e}"
      exit
    else
      $log.xmppd.info "loaded #{@users.length} users"
    end
    return @users
  end
  
  def dump_users users
    begin
      Dir.mkdir('var/db') unless File.exists?('var/db')
      File.open('var/db/users.yaml', 'w') { |f| YAML.dump(users, f) }
    rescue Exception => e
      $log.xmppd.warn "failed to write user database: #{e}"
      return false
    else
      $log.xmppd.info "wrote #{users.length} users"
      @need_dump = false # this check should be in Users
      return true
    end
  end
  
end

end