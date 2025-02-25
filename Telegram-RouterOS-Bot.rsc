#初始化开机启动
onerror error {
    /system scheduler remove Reboot-2min
    /system scheduler remove clearRebootScripts
    } 
onerror error {/system scheduler add name="startup-Telegram-Bot-Scripts" start-time=startup on-event=":execute script=\"Telegram-RouterOS-Bot\""}

#初始化脚本执行，确保不重复执行

:local startJobs [system script job print as-value  where script="Telegram-RouterOS-Bot"]
if ([len $startJobs] > 1) do={   
    :local i 1
    foreach job in $startJobs do={        
        if ([len $startJobs] > $i)  do={
            /system script job remove ($job->".id")
            :set i ($i+1)   
        }         
     }

}

##初始化环境变量
:global updateId 
:if ([:len [/file find where name=updateId.txt]] = 0) do={
    /file print file=updateId
    /file set updateId.txt contents="0"
} else={
    :if ([typeof $updateId] = "nothing") do={  
        :global updateId  [/file get updateId.txt contents]
        /system script run "InitTelegramEnv"
        log info "初始化环境变量"
    }
}


:global botToken
:global chatId
:local telApiDown "https://api.telegram.org/bot$botToken/getUpdates?offset="
#:local telApiUp "https://api.telegram.org/bot$botToken/sendMessage\?chat_id=$chatId&text="


## 如果没有获取到新文件，禁止脚本定时运行，并且一直获取。
/system scheduler set Telegram-RouterOS-Bot-Time  disabled=yes
:local messageIn do={
    :global botToken
    :global chatId
    :global updateId
    :local messageText
    do {        
       onerror error {
            :set messageText  [/deserialize ([/tool fetch url=($telApiDown . $updateId . "&timeout=30")  idle-timeout=30 mode=https  as-value output=user ]->"data") from=json]
       }          
    } while=([len ($messageText ->"result")] = 0 )
    ## 开启脚本自动运行
    log info "有新消息"
    ##开始处理命令
    /log info $messageText
    :local telMcommand ($messageText->"result"->0->"message"->"text")
    :local telMcommand [/pick $telMcommand 1 [len $telMcommand]]
    /log info message="获取的命令为$telMcommand"
    ##获取chatId
    :local telChatId  ($messageText->"result"->0->"message"->"chat"->"id")
    :local messageArray {"telMcommand"=$telMcommand ; "telChatId"=$telChatId}
    #如果有有新消息updateId+1
    if ([len ($messageText ->"result")] != 0 ) do={
          :global updateId (($messageText->"result"->0->"update_id")+1)
    }
    :return $messageArray
}



:local messageArray [$messageIn telApiDown=$telApiDown]
:local telChatId ($messageArray->"telChatId")
:local telMcommand ($messageArray->"telMcommand")

/system scheduler set Telegram-RouterOS-Bot-Time  disabled=no

#定义消息发送函数
:local messageOut [:parse [/system script get messageNotif  source]]
##校验chatId

if ($telChatId = $chatId) do={

    if ($telMcommand = "start") do={
        :local helpText "/openpve MAC启动PVE\n/restart 重启ROUTEROS\n/ip 查询当前pppoe接口的ip地址" 
        [$messageOut  messageText=$helpText]  
        
    }  

    if ($telMcommand = "openpve") do={
        [$messageOut   messageText="开始启动pve"]  
        :execute script="startNas"
        
    } 


    if ($telMcommand = "restart") do={

        [$messageOut  messageText="2分钟后开始重启routeros,回复/clear取消" ]        
        /file set updateId.txt contents=$updateId
        /system scheduler add name="Reboot-2min"  interval=2m on-event="/system reboot"
        /system scheduler add name="clearRebootScripts" start-time=startup on-event="/system scheduler remove Reboot-2min \n/system scheduler remove clearRebootScripts"
        :local testClear true
        while ($testClear) do={
            log info "等待接受取消关机命令"
            :local messageArray [$messageIn telApiDown=$telApiDown]
            #log info "telMcommand为$telMcommand"
            if (($messageArray->"telMcommand") = "clear") do={
               # log info "开始取消"
                :local testClear false
                [$messageOut  messageText="计划关机已经取消"]           
                /system scheduler remove Reboot-2min
                /system scheduler remove clearRebootScripts
            }
        }
    } 

    if ($telMcommand = "ip") do={

        :local pubIP [ip address get [/ip address find interface=pppoe-out1] address]
        [$messageOut  messageText=("公网ip地址为" . $pubIP)]     
    } 


} else={
    :if ($fileInfo) do={  
         /tool fetch url="https://api.telegram.org/bot$botToken/sendMessage\?chat_id=$telChatId&text=非法消息" keep-result=no
    }
}
