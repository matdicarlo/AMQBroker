package mqttpub;

import org.apache.camel.builder.RouteBuilder;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.concurrent.atomic.AtomicLong;
import org.apache.camel.component.paho.mqtt5.PahoMqtt5Constants;
import org.eclipse.paho.mqttv5.common.packet.MqttProperties;
import org.eclipse.paho.mqttv5.common.packet.UserProperty;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
public class GenerateMessagesRoute extends RouteBuilder {

    private final AtomicLong counter = new AtomicLong(1);
    private final String payloadBase = "A".repeat(250);

    @ConfigProperty(name = "context.trace", defaultValue = "false")
    boolean contextTrace;

    @ConfigProperty(name = "timer.replicas", defaultValue = "1")
    int timerReplicas;

    @ConfigProperty(name = "timer.period", defaultValue = "1")
    int timerPeriod;

    @ConfigProperty(name = "timer.repeatCount", defaultValue = "0")
    int timerRepeatCount;

    @ConfigProperty(name = "timer.delay", defaultValue = "1000")
    int timerDelay;

    @ConfigProperty(name = "seda.concurrentConsumers", defaultValue = "10")
    int concurrentConsumers;

    @ConfigProperty(name = "brokeraddress", defaultValue = "localhost")
    String brokerAddress;

    @ConfigProperty(name = "brokerport", defaultValue = "1883")
    String brokerPort;

    @ConfigProperty(name = "mqtt.qos", defaultValue = "1")
    int qos;

    @ConfigProperty(name = "mqtt.cleanStart", defaultValue = "false")
    boolean cleanStart;

    @ConfigProperty(name = "mqtt.sessionExpiryInterval", defaultValue = "4294967295")
    long sessionExpiryInterval;

    @ConfigProperty(name = "retry.count", defaultValue = "5")
    int retryCount;

    @ConfigProperty(name = "retry.delay", defaultValue = "250")
    long retryDelay;

    @ConfigProperty(name = "mqtt.remoteURI")
    String remoteURI;

    @Override
    public void configure() throws Exception {
        getCamelContext().setTracing(contextTrace);

        onException(Exception.class)
                .id("onException")
                .handled(true)
                .logStackTrace(false)
                .maximumRedeliveries(retryCount)
                .redeliveryDelay(retryDelay);

        if (timerReplicas < 1) {
            return;
        }

        for (int i = 1; i <= timerReplicas; i++) {
            from(String.format("timer://stream%03d?fixedRate=true&period=%d&repeatCount=%d&delay=%d", i, timerPeriod, timerRepeatCount, timerDelay))
                    .id("generateMessages" + i)
                    .to(String.format("seda:publisher?size=%d&blockWhenFull=true", Integer.MAX_VALUE - 1))
                    .id("sendEvent" + i);
        }

        from("seda:publisher?concurrentConsumers=" + concurrentConsumers)
                .id("createMessage")
                .process(exchange -> {
                    long currentCount = counter.getAndIncrement();
                    String uniquePayload = String.format("[ID:%d]-%s", currentCount, payloadBase);
                    exchange.getIn().setBody(uniquePayload);

                    MqttProperties mqttProps = new MqttProperties();
                    mqttProps.getUserProperties().add(new UserProperty("MQPERF_counter", String.valueOf(currentCount)));
                    mqttProps.getUserProperties().add(new UserProperty("MQPERF_time", String.valueOf(System.currentTimeMillis())));
                    exchange.getIn().setHeader(PahoMqtt5Constants.CAMEL_PAHO_MSG_PROPERTIES, mqttProps);
                })
                .id("createMessagePayload")
                .to("direct:processMessage")
                .id("processCreatedMessage");

        from("direct:processMessage")
                .id("processMessage")
                .to("paho-mqtt5:testqueue?qos=" + qos +
                        "&brokerUrl=" + remoteURI +
                        "&cleanStart=" + cleanStart +
                        "&sessionExpiryInterval=" + sessionExpiryInterval +
                        "&automaticReconnect=true" +
                        "&connectionTimeout=10" +
                        "&keepAliveInterval=10")
                .id("publishMessage")
				.process(exchange -> {
					MqttProperties props = exchange.getIn().getHeader(PahoMqtt5Constants.CAMEL_PAHO_MSG_PROPERTIES, MqttProperties.class);
					System.out.println("MQTT5 User Properties published: " + props.getUserProperties().toString());
				})
                .id("logPublishedMessage");
    }
}