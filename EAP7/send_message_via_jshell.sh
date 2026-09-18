jshell --class-path "/opt/jboss-eap-7/jboss-eap-7.4/bin/client/jboss-client.jar" << 'EOF'
import javax.naming.*;
import javax.jms.*;
import java.util.Properties;

Properties p = new Properties();
p.put(Context.INITIAL_CONTEXT_FACTORY, "org.wildfly.naming.client.WildFlyInitialContextFactory");
p.put(Context.PROVIDER_URL, "http-remoting://127.0.0.1:8080");

p.put(Context.SECURITY_PRINCIPAL, "guest");
p.put(Context.SECURITY_CREDENTIALS, "guest");

try {
    InitialContext ctx = new InitialContext(p);
    ConnectionFactory cf = (ConnectionFactory) ctx.lookup("jms/RemoteConnectionFactory");
    javax.jms.Queue queue = (javax.jms.Queue) ctx.lookup("jms/queue/TEST_QUEUE");

    try (Connection conn = cf.createConnection("guest", "guest");
         Session sess = conn.createSession(false, Session.AUTO_ACKNOWLEDGE);
         MessageProducer prod = sess.createProducer(queue)) {
        
        TextMessage msg = sess.createTextMessage("Test Failure Message Isolation");
        prod.send(msg);
        System.out.println("\n>>> SUCCESS: Message sent to TEST_QUEUE! <<<\n");
    }
} catch(Exception e) { e.printStackTrace(); }
/exit
EOF
