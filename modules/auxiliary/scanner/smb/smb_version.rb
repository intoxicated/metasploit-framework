##
# This module requires Metasploit: http//metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##


require 'msf/core'


class Metasploit3 < Msf::Auxiliary


  # Exploit mixins should be called first
  include Msf::Exploit::Remote::DCERPC
  include Msf::Exploit::Remote::SMB
  include Msf::Exploit::Remote::SMB::Authenticated

  # Scanner mixin should be near last
  include Msf::Auxiliary::Scanner
  include Msf::Auxiliary::Report

  # Aliases for common classes
  SIMPLE = Rex::Proto::SMB::SimpleClient
  XCEPT  = Rex::Proto::SMB::Exceptions
  CONST  = Rex::Proto::SMB::Constants


  def initialize
    super(
      'Name'        => 'SMB Version Detection',
      'Description' => 'Display version information about each system',
      'Author'      => 'hdm',
      'License'     => MSF_LICENSE
    )

    deregister_options('RPORT')
  end

  def rport
    @rport || datastore['RPORT']
  end

  def smb_direct
    @smbdirect || datastore['SMBDirect']
  end

  # Fingerprint a single host
  def run_host(ip)
    [[445, true], [139, false]].each do |info|

    @rport = info[0]
    @smbdirect = info[1]
    self.simple = nil

    begin
      res = smb_fingerprint()

      if(res['os'] and res['os'] != 'Unknown')

        case res['os']
        when /Windows/
          os = OperatingSystems::WINDOWS
        else
          case res['sp']
          when /apple/
            os = OperatingSystems::MAC_OSX
            res['os'] = 'Mac OS X'
          when /ubuntu/
            os = OperatingSystems::LINUX
            res['os'] = 'Ubuntu'
          when /debian/
            os = OperatingSystems::LINUX
            res['os'] = 'Debian'
          else
            os = OperatingSystems::UNKNOWN
          end
        end

        desc = "#{res['os']} #{res['sp']} (language: #{res['lang']})"
        if(simple.client.default_name)
          desc << " (name:#{simple.client.default_name})"
        end

        if(simple.client.default_domain)
          desc << " (domain:#{simple.client.default_domain})"
        end

        print_status("#{rhost}:#{rport} is running #{desc}")

        report_service(
          :host  => ip,
          :port  => info[0],
          :proto => 'tcp',
          :name  => 'smb',
          :info  => desc
        )

        conf = {
          :os_flavor => res['os'],
          :os_name => os,
        }

        conf[:os_sp]   = res['sp']   if res['sp']
        conf[:os_lang] = res['lang'] if res['os'] =~ /Windows/
        conf[:SMBName] = simple.client.default_name if simple.client.default_name
        conf[:SMBDomain] = simple.client.default_domain if simple.client.default_domain

        report_note(
          :host  => ip,
          :port  => info[0],
          :proto => 'tcp',
          :ntype => 'smb.fingerprint',
          :data  => conf
        )

      else
        report_service(:host => ip, :port => info[0], :name => 'smb')
        print_status("#{rhost} could not be identified")
      end

      disconnect

      break

    rescue ::Rex::Proto::SMB::Exceptions::NoReply => e
      next
    rescue ::Rex::Proto::SMB::Exceptions::ErrorCode  => e
      next
    rescue ::Rex::Proto::SMB::Exceptions::LoginError => e
      # Vista has 139 open but doesnt like *SMBSERVER
      if(e.to_s =~ /server refused our NetBIOS/)
        next
      end

      return
    rescue ::Timeout::Error
    rescue ::Rex::ConnectionError
      next

    rescue ::Exception => e
      print_error("#{rhost}: #{e.class} #{e}")
    ensure
      disconnect
    end
    end
  end

end
