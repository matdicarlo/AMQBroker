package mqttsub;

import org.apache.camel.builder.RouteBuilder;
import jakarta.enterprise.context.ApplicationScoped;
import org.apache.camel.component.paho.mqtt5.PahoMqtt5Constants;
import org.eclipse.paho.mqttv5.common.packet.MqttProperties;
import org.eclipse.paho.mqttv5.common.packet.UserProperty;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
public class ConsumeMessagesRoute extends RouteBuilder {

	// --- Core MQTT Configurations ---
	@ConfigProperty(name = "brokeraddress", defaultValue = "localhost")
	String brokerAddress;

	@ConfigProperty(name = "brokerport", defaultValue = "1883")
	String brokerPort;

	@ConfigProperty(name = "mqtt.qos", defaultValue = "1")
	int qos;

	@ConfigProperty(name = "mqtt.clientId", defaultValue = "mqtt-subscriber-fixed-id")
	String clientId;

	@ConfigProperty(name = "mqtt.sessionExpiryInterval", defaultValue = "4294967295")
	long sessionExpiryInterval;

	@ConfigProperty(name = "mqtt.remoteURI")
	String remoteURI;

	@Override
	public void configure() throws Exception {

		boolean cleanStart = qos == 0;
		long effectiveSessionExpiryInterval = qos >= 1 ? sessionExpiryInterval : 0L;

		from("paho-mqtt5:testqueue"
				+ "?brokerUrl=" + remoteURI
				+ "&qos=" + qos
				+ "&clientId=" + clientId
				+ "&cleanStart=" + cleanStart
				+ "&sessionExpiryInterval=" + effectiveSessionExpiryInterval
				+ "&automaticReconnect=true")
				.id("consumeMessages")
				.to("seda:handleMessage?size=1000000&blockWhenFull=true")
				.id("handleMessage");

		from("seda:handleMessage?concurrentConsumers=10")
				.id("receiveMessage")

				.process(exchange -> {
					MqttProperties props = exchange.getIn().getHeader(PahoMqtt5Constants.CAMEL_PAHO_MSG_PROPERTIES, MqttProperties.class);
					if (props != null && props.getUserProperties() != null) {
						System.out.println("MQTT5 User Properties received: " + props.getUserProperties().toString());
					}
				})
				.id("mqtt5UserPropertiesProcessor");
	}
}
