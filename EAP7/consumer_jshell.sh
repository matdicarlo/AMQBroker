jshell --class-path "/opt/jboss-eap-7/jboss-eap-7.4/bin/client/jboss-client.jar" << 'EOF'
import javax.naming.*;
import javax.jms.*;
import java.util.Properties;

// Get the exact PID of this running JShell execution instance
long pid = ProcessHandle.current().pid();

Properties p = new Properties();
p.put(Context.INITIAL_CONTEXT_FACTORY, "org.wildfly.naming.client.WildFlyInitialContextFactory");
p.put(Context.PROVIDER_URL, "http-remoting://127.0.0.1:8080");
p.put(Context.SECURITY_PRINCIPAL, "guest");
p.put(Context.SECURITY_CREDENTIALS, "guest");

try {
    InitialContext ctx = new InitialContext(p);
    ConnectionFactory cf = (ConnectionFactory) ctx.lookup("jms/RemoteConnectionFactory");
    javax.jms.Queue queue = (javax.jms.Queue) ctx.lookup("jms/queue/TEST_QUEUE");

    Connection conn = cf.createConnection("guest", "guest");
    Session sess = conn.createSession(false, Session.CLIENT_ACKNOWLEDGE);
    MessageConsumer cons = sess.createConsumer(queue);
    
    conn.start();
    System.out.println("\n=================================================");
    System.out.println(">>> CONSUMER ACTIVE (PID: " + pid + ") Waiting for payload...");
    System.out.println("=================================================\n");
    
    TextMessage msg = (TextMessage) cons.receive(15000); // 15 second receive window
    
    if (msg != null) {
        System.out.println("\n>>> [STAGE 1] TARGET PAYLOAD GRABBED!");
        System.out.println(">>> Message Content: \"" + msg.getText() + "\"");
        System.out.println("\n>>> [STAGE 2] HOLDING DELIVERY IN-FLIGHT FOR 20 SECONDS...");
        System.out.println("\n RUN THIS IN YOUR OTHER TERMINAL TAB RIGHT NOW:");
        System.out.println(" =========================================");
        System.out.println("  kill -9 " + pid);
        System.out.println(" =========================================");
        System.out.println("\n>>> Waiting...");
        
        // Sleep window to let you fire the kill command
        Thread.sleep(20000);
        
        msg.acknowledge();
        System.out.println("\n>>> Test Failed: Message acknowledged because process wasn't killed in time.");
    } else {
        System.out.println("\n>>> Timeout: No message found on TEST_QUEUE. Run the producer first.");
    }
    
    conn.close();
} catch(Exception e) { 
    System.out.println("\n>>> Connection broken ungracefully! (Expected behavior during kill) <<<");
}
/exit
EOF

