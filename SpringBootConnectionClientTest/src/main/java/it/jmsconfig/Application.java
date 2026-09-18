package it.jmsconfig;

import jakarta.ejb.ActivationConfigProperty;
import jakarta.ejb.MessageDriven;
import jakarta.jms.Message;
import jakarta.jms.MessageListener;
import jakarta.jms.TextMessage;
import org.jboss.ejb3.annotation.ResourceAdapter; // Requires the dependency above
import java.util.logging.Logger;

/*
@MessageDriven(name = "TestMDB", activationConfig = {
        @ActivationConfigProperty(propertyName = "destinationLookup", propertyValue = "TestQueue"),
        @ActivationConfigProperty(propertyName = "destinationType", propertyValue = "jakarta.jms.Queue"),
        @ActivationConfigProperty(propertyName = "clientId", propertyValue = "EAP8-MDB-TEST-CLIENT"),
        @ActivationConfigProperty(propertyName = "subscriptionName", propertyValue = "MyTestSub")
})
*/

@MessageDriven(activationConfig = {
        @ActivationConfigProperty(propertyName = "destinationLookup", propertyValue = "jms/queue/TestQueue"),
        @ActivationConfigProperty(propertyName = "destinationType", propertyValue = "jakarta.jms.Queue"),
        @ActivationConfigProperty(propertyName = "clientID", propertyValue = "TESTCLIENTID"),
        @ActivationConfigProperty(propertyName = "subscriptionName", propertyValue = "MyMdbSubscription")
})
@ResourceAdapter("remote-artemis-ra")
public class Application implements MessageListener {

    private static final Logger LOGGER = Logger.getLogger(Application.class.getName());

    @Override
    public void onMessage(Message message) {
        try {
            if (message instanceof TextMessage) {
                LOGGER.info(">>> MDB RECEIVED: " + ((TextMessage) message).getText());
            }
        } catch (Exception e) {
            LOGGER.severe("MDB Processing Error: " + e.getMessage());
        }
    }
}