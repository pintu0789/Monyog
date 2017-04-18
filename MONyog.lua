-- If there is a change in this LUA we have to update that here 
local MONYOG_VERSION = "3.1"

local PROXY_VERSION_SUPPORTED_BY_MONYOG = 0x00601

-- Patch for windows version of 0.72
local PROXY_VERSION_WIN_PATCH = 0x0072

local PROXY_NOT_SUPPORTED_ERROR = "This proxy version is not supported by MONyog"

local MAX_QUERY_COUNT_BEFORE_CLEAR = 8192

-- init query counters
if not proxy.global.MONyogQueries then
	proxy.global.MONyogQueries = { }
end

-- intialize query counter variable
if not proxy.global.MONyogQueryCounter then
	proxy.global.MONyogQueryCounter = 0
end

-- By default collection will be false
 if not proxy.global.MONyogIsCollecting then
	proxy.global.MONyogIsCollecting = false
 end

proxy.global.WrongProxyVersion = false

 -- Query is processed before sending to the server in this function
function read_query(pPacket)
	
	local command
	
	-- Query string is fetched here
	if string.byte(pPacket) == proxy.COM_QUERY then
				
		-- TrimRight is required to trim trailing '\n' after the string is fetched. 
		-- We are using string.sub(pPacket, 2) because first character will have type.
		command = TrimRight(string.sub(pPacket, 2))
		
		-- If it is version then we will return current version
		if command == "VERSION" then
			
			-- Get the current version of qd.lua
			MONyogGetVersion()
			
			-- Send this back to client
			return proxy.PROXY_SEND_RESULT
			
		-- If the Command is Fetch then create resultset and fill up the resultset for sending
		elseif command == "FETCH" then
			
			-- Resultset is created here
			MONyogFetch()
	  				
			-- Re-initialize the counter and record array
			proxy.global.MONyogQueryCounter = 0
    		proxy.global.MONyogQueries = {}
	  			
			-- Send this back to client
  			return proxy.PROXY_SEND_RESULT
	  			
		-- If the command is START then start collecting query records from now
		elseif command == "START" then
			proxy.global.MONyogIsCollecting = true
			
			proxy.response = {
							  type = proxy.MYSQLD_PACKET_OK,
							 }
			return proxy.PROXY_SEND_RESULT
								 
		-- If the command is STOP then stop collecting query records from now
		elseif command == "STOP" then
			proxy.global.MONyogIsCollecting = false
			
			proxy.response = {
						      type = proxy.MYSQLD_PACKET_OK,
						     }
			return proxy.PROXY_SEND_RESULT
	     
	end  -- End of elseif ladder
		
		-- Only if the command is START append the query to queue
		if proxy.global.MONyogIsCollecting == true then
			
			proxy.queries:append(0, pPacket)
			return proxy.PROXY_SEND_QUERY
			
		end	
		
	end -- End of "if string.byte(pPacket) == proxy.COM_QUERY" 
	
end  -- End of read_query()

-- This function executes once a query appended to the queue has finished execution(successful or unsuccessful)
function read_query_result(pInj) 
	
	local iserror	= false
	local res		= assert(pInj.resultset)
	
	-- id = 1 is the default id we are sending while appending to the queue
	if pInj.id == 0 then
	
		-- the query failed, dont consider it.
		if not res.query_status or res.query_status == proxy.MYSQLD_PACKET_ERR then
			return
			
		end
		
	end -- End of "if inj.id == 0"
		
	if pInj.query:byte() == proxy.COM_QUERY then
		
		MONyogInsert(pInj)
	    
	end -- End of "if cmd.type == proxy.COM_QUERY"
	
end -- End of read_query_result(pInj)

-- Construct a result set with current version number
function MONyogGetVersion()

-- Construct field name
	ConstructVersionHeader();
	
-- Set the actual version to the row array
	SetVersion();
	
end

-- Construct field name "Version" and "Message",
-- On clicking 'Test Proxy', we are sending MONyog.lua version
-- and message if MySQL proxy is greater than or equal to
-- 0.6.1
function ConstructVersionHeader()
	
	proxy.response = 
	{
		type = proxy.MYSQLD_PACKET_OK,
		resultset = 
		{
			fields = 
			{
				{ 
					type = proxy.MYSQL_TYPE_STRING,
					name = "Version" 
				
				},
				{ 
					type = proxy.MYSQL_TYPE_STRING,
					name = "Message" 
				
				},
			}
		}
	}
	
end

-- Set the actual version to the row array
function SetVersion()
	
	local rows = {}
	local okstr = "ok"
	
	-- Set the row, first column MONyog.lua version, should correspond to 
	-- LUA version defined in common.h, second parameter is checking whether 
	-- MySQL proxy version is atleast 0.6.1 and onwards. 
	rows[1] = {MONYOG_VERSION, ProxyVersionValidate(okstr)};
	
  -- Copy the version and set it to response
	proxy.response.resultset.rows = rows
		
end -- End of SetVersion()

-- Used to check the proxy version, If it is greater than or equal to 0.6.1
-- returns OK else returns with the error message

function ProxyVersionValidate(pCorrectStatusString)

	-- Patch since 0.72 windows version did not return correct version string.
	if(proxy.PROXY_VERSION == PROXY_VERSION_WIN_PATCH) then
		return pCorrectStatusString
		
	end --End of if(proxy.PROXY_VERSION == PROXY_VERSION_WIN_PATCH)
	
	if proxy.PROXY_VERSION <  PROXY_VERSION_SUPPORTED_BY_MONYOG then
		return PROXY_NOT_SUPPORTED_ERROR
	else
		return pCorrectStatusString
	end

end -- End of ProxyVersionValidate(pCorrectStatusString)

-- This function is used to Create resultset
function MONyogFetch()

  ConstructFields()
  ConstructRows()

end	-- End of HandleFetchCommand()

-- This function is used to Construct fields of the 
function ConstructFields()
  	
	proxy.response = 
	{
		type = proxy.MYSQLD_PACKET_OK,
		resultset = 
		{
			fields = 
			{
				{ 
					type = proxy.MYSQL_TYPE_STRING,
					name = "Query" 
				},
				{ 
					type = proxy.MYSQL_TYPE_LONG,
					name = "Query_occurence_time" 
				}, 
				{ 
					type = proxy.MYSQL_TYPE_LONG,
					name = "Query_time" 
				},
				{ 
					type = proxy.MYSQL_TYPE_STRING,
					name = "User" 
				},
				{ 
					type = proxy.MYSQL_TYPE_STRING,
					name = "Host" 
				},
			}
		}
	}
	
end --End of ConstructFields()

function ConstructRows()

	local rows = {}
	local counter = 0			
	local noofelements
	local strok = "ok"
	
	if proxy.global.MONyogQueries then
	
		-- number of records collected
		noofelements = proxy.global.MONyogQueryCounter

			-- Copy all collected values into an array			
			while (counter + 1) <= noofelements do
				
				rows[counter + 1] = {
										proxy.global.MONyogQueries[counter].Query,
										os.time(), 
										proxy.global.MONyogQueries[counter].Query_time,
										proxy.global.MONyogQueries[counter].User,
										proxy.global.MONyogQueries[counter].Host
									}
				counter = counter + 1
				
			end -- End of while loop
		
	end -- End of "if proxy.global.MONyogQueries"

	-- Copy the row array to the resultset			
	proxy.response.resultset.rows = rows
	
end	-- End of ConstructRows
      
-- This function inserts a record of query in the array
function MONyogInsert(pInj)
	
	local querytimetaken
	local query
	local strok = "ok"
		
	-- Calculate the total query time taken, i.e
	-- number of microseconds required to (receive the last row of the result set) - (required to receive the first row)
	querytimetaken = pInj.query_time

	-- Except the COM_QUERY part fetch only the query
	query = TrimRight(pInj.query:sub(2))
	
	-- Mechanism to limit number of query records to "MAX_QUERY_COUNT_BEFORE_CLEAR" in case MONyog crashes or stopped
	-- in between
	if proxy.global.MONyogQueryCounter >= MAX_QUERY_COUNT_BEFORE_CLEAR then
		
		-- empty the array
		proxy.global.MONyogQueries = {}
		
		-- initialize the counter
		proxy.global.MONyogQueryCounter = 0
		
	end	--"if proxy.global.MONyogQueryCounter >= MAX_QUERY_COUNT_BEFORE_CLEAR then"		
	
	-- Initialization of MONyog query array
	if not proxy.global.MONyogQueries[proxy.global.MONyogQueryCounter] then

		InitializeMONyogQueries()

	end -- "if not proxy.global.MONyogQueries[proxy.global.MONyogQueryCounter]"
	
	-- Either the query or the error message is stored. Error occurs if there is a version mismatch
	proxy.global.MONyogQueries[proxy.global.MONyogQueryCounter].Query = ProxyVersionValidate(query)
	
	if ProxyVersionValidate(strok) == strok	then
	
		proxy.global.MONyogQueries[proxy.global.MONyogQueryCounter].Query_time = querytimetaken/1000000
		
		-- Microseconds are converted to seconds while storing
		proxy.global.MONyogQueryCounter = proxy.global.MONyogQueryCounter + 1
		
	else
		
		proxy.global.MONyogQueryCounter = 1	
		
	end -- end of "if ProxyVersionValidate(strok) == strok"
	
end	-- End of InsertRecord(pInj)

function InitializeMONyogQueries()

proxy.global.MONyogQueries[proxy.global.MONyogQueryCounter] = {
																Query = "", 
																Query_occurence_time = 0,
																Query_time = 0,
																User = "",
																Host = ""
	    														} 
end -- function InitializeMONyogQueries()									

-- Trims trailing whitespaces, tabs, carriage returs, linefeed if any

function TrimRight(pStr)

	return (string.gsub(pStr, "[ \t\n\r]+$", ""))
	
end -- End of TrimRight(pStr)
