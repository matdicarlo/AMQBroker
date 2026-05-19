package it.producer.ProducerService;

import jakarta.jms.ConnectionFactory;
import org.apache.camel.Exchange;
import org.apache.camel.Processor;
import org.apache.camel.builder.RouteBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.jms.connection.JmsTransactionManager;
import org.springframework.stereotype.Component;

@Component
public class ProducerRouteBuilder extends RouteBuilder {

    private static final Logger log = LoggerFactory.getLogger(ProducerRouteBuilder.class);

    @Override
    public void configure() throws Exception {



        onException(Exception.class)
                .process(new Processor() {
                    @Override
                    public void process(Exchange exchange) throws Exception {
                        Exception exception = exchange.getProperty(Exchange.EXCEPTION_CAUGHT, Exception.class);
                        exception.printStackTrace();
                    }
                })
                .handled(true);


        from("direct:message-producer")
                .routeId("jmsProducerRoute")
                .transacted()
/*
//splits messages if needed to send to multiple queues
                .process(exchange -> {
                    StringBuilder bigMessage = new StringBuilder();
//                    for (int i = 0; i < 1000; i++) {
                    for (int i = 0; i < 10; i++) {
                        bigMessage.append("Hello part ").append(i).append(" ");
                    }
                    exchange.getIn().setBody(bigMessage.toString());
                    log.info("Generated big message of size: {} chars", bigMessage.length());
                })
                .split(body().tokenize(" "))
                .parallelProcessing()
                .process(exchange -> {
                    String partMessage = exchange.getIn().getBody(String.class);
                    log.info("Splitting message part: {}", partMessage);
                })
                .multicast()
                .parallelProcessing()
*/
                .to("jms:queue:simplequeue")
                .end()
                .log("Message parts successfully sent to AMQ queues: ${body}");



    }




    @Bean
    public JmsTransactionManager jmsTransactionManager(ConnectionFactory connectionFactory) {
        return new JmsTransactionManager(connectionFactory);
    }
}


